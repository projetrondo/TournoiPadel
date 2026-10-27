<?php

declare(strict_types=1);

namespace App\Security;

use Symfony\Component\Security\Core\Exception\BadCredentialsException;
use Symfony\Component\Security\Http\AccessToken\AccessTokenHandlerInterface;
use Symfony\Component\Security\Http\Authenticator\Passport\Badge\UserBadge;

/**
 * Vérifie le jeton d'accès envoyé par l'app (`Authorization: Bearer …`).
 */
final readonly class AccessTokenHandler implements AccessTokenHandlerInterface
{
    public function __construct(private TokenIssuer $tokens)
    {
    }

    public function getUserBadgeFrom(#[\SensitiveParameter] string $accessToken): UserBadge
    {
        try {
            return new UserBadge($this->tokens->verify($accessToken));
        } catch (InvalidToken $exception) {
            // 401 : l'app renouvelle alors son jeton. Le motif exact reste côté serveur.
            throw new BadCredentialsException('Jeton refusé.', previous: $exception);
        }
    }
}
