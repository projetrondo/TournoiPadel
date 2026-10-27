<?php

declare(strict_types=1);

namespace App\Auth;

use App\Entity\LoginAttempt;
use App\Entity\User;
use App\Repository\LoginAttemptRepository;
use Doctrine\ORM\EntityManagerInterface;
use Psr\Clock\ClockInterface;

/**
 * Connexion Google depuis l'app iPhone, en trois temps (voir `LoginAttempt`).
 */
final readonly class GoogleSignIn
{
    public function __construct(
        private GoogleProvider $google,
        private AccountResolver $accounts,
        private LoginAttemptRepository $attempts,
        private EntityManagerInterface $entityManager,
        private ClockInterface $clock,
        private string $publicUrl,
        private string $appCallbackUrl,
    ) {
    }

    public function isAvailable(): bool
    {
        return $this->google->isConfigured();
    }

    /**
     * 1. Ouvre une tentative et rend l'adresse Google où envoyer l'utilisateur.
     *
     * @throws AuthFailed
     */
    public function start(string $codeChallenge): string
    {
        if (!$this->google->isConfigured()) {
            throw new AuthFailed('La connexion avec Google n\'est pas configurée.');
        }
        // Condensé SHA-256 en base64url : 43 caractères.
        if (1 !== preg_match('/^[A-Za-z0-9_-]{43}$/', $codeChallenge)) {
            throw new AuthFailed('Demande de connexion invalide.');
        }
        $state = bin2hex(random_bytes(32));
        $this->entityManager->persist(new LoginAttempt(self::hash($state), $codeChallenge, $this->clock->now()));
        $this->entityManager->flush();

        return $this->google->authorizationUrl($state, $this->redirectUri());
    }

    /**
     * 2. Retour de Google : rend l'adresse de retour dans l'app, avec un code de passage
     * ou un message d'erreur. Ne lève jamais : l'utilisateur doit toujours revenir à l'app.
     */
    public function callback(?string $code, ?string $state, ?string $error): string
    {
        $now = $this->clock->now();
        $attempt = null !== $state ? $this->attempts->findOneBy(['stateHash' => self::hash($state)]) : null;
        if (null === $attempt || !$attempt->isAwaitingProvider($now)) {
            return $this->appUrl(['error' => 'Cette demande de connexion n\'est plus valable. Recommencez.']);
        }
        if (null !== $error || null === $code) {
            $attempt->spend($now);
            $this->entityManager->flush();

            return $this->appUrl(['error' => 'access_denied' === $error ? 'cancelled' : 'Google a refusé la connexion.']);
        }

        try {
            $user = $this->accounts->resolve($this->google->exchange($code, $this->redirectUri()));
        } catch (AuthFailed $failure) {
            $attempt->spend($now);
            $this->entityManager->flush();

            return $this->appUrl(['error' => $failure->getMessage()]);
        }

        $handoff = bin2hex(random_bytes(32));
        $attempt->issueHandoff($user, self::hash($handoff), $now);
        $this->entityManager->flush();

        return $this->appUrl(['handoff' => $handoff]);
    }

    /**
     * 3. L'app échange le code de passage, en prouvant qu'elle a démarré la connexion.
     *
     * @throws AuthFailed
     */
    public function redeem(#[\SensitiveParameter] string $handoff, #[\SensitiveParameter] string $codeVerifier): User
    {
        $now = $this->clock->now();
        $attempt = $this->attempts->findOneBy(['handoffHash' => self::hash($handoff)]);
        if (null === $attempt || !$attempt->isHandoffUsable($now)) {
            throw new AuthFailed('Ce lien de connexion n\'est plus valable. Recommencez.');
        }
        // Dépensé avant toute vérification : un code de passage ne sert qu'une fois, même raté.
        $attempt->spend($now);
        $this->entityManager->flush();

        $challenge = rtrim(strtr(base64_encode(hash('sha256', $codeVerifier, true)), '+/', '-_'), '=');
        if (!hash_equals($attempt->getCodeChallenge(), $challenge)) {
            throw new AuthFailed('Cette connexion n\'a pas été demandée par cet appareil.');
        }

        /** @var User */
        return $attempt->getUser();
    }

    public function redirectUri(): string
    {
        return rtrim($this->publicUrl, '/').'/auth/google/callback';
    }

    /** @param array<string, string> $query */
    private function appUrl(array $query): string
    {
        return $this->appCallbackUrl.'?'.http_build_query($query);
    }

    private static function hash(string $secret): string
    {
        return hash('sha256', $secret);
    }
}
