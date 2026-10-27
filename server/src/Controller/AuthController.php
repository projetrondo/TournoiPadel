<?php

declare(strict_types=1);

namespace App\Controller;

use App\Auth\AccountResolver;
use App\Auth\AppleIdentityVerifier;
use App\Auth\AuthFailed;
use App\Auth\GoogleSignIn;
use App\Security\SessionManager;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\RedirectResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\RateLimiter\RateLimiterFactory;
use Symfony\Component\Routing\Attribute\Route;

/**
 * Connexion de l'app : Google, Apple, renouvellement et déconnexion.
 * Chaque réponse de connexion contient `accessToken`, `refreshToken`, `expiresIn` et `account`.
 */
#[Route('/auth')]
final class AuthController
{
    use JsonRequest;

    public function __construct(
        private readonly GoogleSignIn $google,
        private readonly AppleIdentityVerifier $apple,
        private readonly AccountResolver $accounts,
        private readonly SessionManager $sessions,
        private readonly RateLimiterFactory $authLimiter,
    ) {
    }

    /** Modes de connexion disponibles sur ce serveur (l'app n'affiche que ceux-là). */
    #[Route('/providers', methods: ['GET'])]
    public function providers(): JsonResponse
    {
        return new JsonResponse(['google' => $this->google->isAvailable(), 'apple' => true]);
    }

    #[Route('/google/start', methods: ['POST'])]
    public function googleStart(Request $request): JsonResponse
    {
        $this->throttle($request);
        try {
            return new JsonResponse(['authorizationUrl' => $this->google->start(self::string(self::body($request), 'codeChallenge'))]);
        } catch (AuthFailed $failure) {
            return self::error($failure->getMessage(), Response::HTTP_UNPROCESSABLE_ENTITY);
        }
    }

    /** Retour de Google, dans le navigateur de connexion : renvoie vers l'app. */
    #[Route('/google/callback', methods: ['GET'])]
    public function googleCallback(Request $request): RedirectResponse
    {
        return new RedirectResponse($this->google->callback(
            $request->query->getString('code') ?: null,
            $request->query->getString('state') ?: null,
            $request->query->getString('error') ?: null,
        ));
    }

    #[Route('/google/redeem', methods: ['POST'])]
    public function googleRedeem(Request $request): JsonResponse
    {
        $this->throttle($request);
        $body = self::body($request);
        try {
            $user = $this->google->redeem(self::string($body, 'handoff'), self::string($body, 'codeVerifier'));
        } catch (AuthFailed $failure) {
            return self::error($failure->getMessage(), Response::HTTP_UNAUTHORIZED);
        }

        return new JsonResponse($this->sessions->open($user) + ['account' => AccountController::describe($user)]);
    }

    #[Route('/apple', methods: ['POST'])]
    public function apple(Request $request): JsonResponse
    {
        $this->throttle($request);
        $body = self::body($request);
        $name = \is_string($body['name'] ?? null) ? $body['name'] : null;
        try {
            $identity = $this->apple->verify(self::string($body, 'identityToken'), self::string($body, 'nonce'), $name);
        } catch (AuthFailed $failure) {
            return self::error($failure->getMessage(), Response::HTTP_UNAUTHORIZED);
        }
        $user = $this->accounts->resolve($identity);

        return new JsonResponse($this->sessions->open($user) + ['account' => AccountController::describe($user)]);
    }

    #[Route('/refresh', methods: ['POST'])]
    public function refresh(Request $request): JsonResponse
    {
        $this->throttle($request);
        $tokens = $this->sessions->refresh(self::string(self::body($request), 'refreshToken'));
        if (null === $tokens) {
            return self::error('Session expirée. Reconnectez-vous.', Response::HTTP_UNAUTHORIZED);
        }

        return new JsonResponse($tokens);
    }

    #[Route('/logout', methods: ['POST'])]
    public function logout(Request $request): Response
    {
        $this->sessions->close(self::string(self::body($request), 'refreshToken'));

        return new Response(null, Response::HTTP_NO_CONTENT);
    }

    private function throttle(Request $request): void
    {
        $limit = $this->authLimiter->create($request->getClientIp() ?? 'inconnu')->consume();
        if (!$limit->isAccepted()) {
            throw new \Symfony\Component\HttpKernel\Exception\TooManyRequestsHttpException(
                $limit->getRetryAfter()->getTimestamp() - time(),
                'Trop de tentatives. Réessayez dans quelques minutes.',
            );
        }
    }
}
