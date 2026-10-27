<?php

declare(strict_types=1);

namespace App\Security;

use App\Entity\RefreshToken;
use App\Entity\User;
use App\Repository\RefreshTokenRepository;
use Doctrine\ORM\EntityManagerInterface;
use Psr\Clock\ClockInterface;

/**
 * Ouvre, renouvelle et ferme les sessions de l'app : un jeton d'accès court et un jeton
 * de renouvellement long, à usage unique.
 */
final readonly class SessionManager
{
    public function __construct(
        private TokenIssuer $tokens,
        private RefreshTokenRepository $refreshTokens,
        private EntityManagerInterface $entityManager,
        private ClockInterface $clock,
    ) {
    }

    /** @return array{accessToken: string, refreshToken: string, expiresIn: int} */
    public function open(User $user): array
    {
        $now = $this->clock->now();
        $refresh = bin2hex(random_bytes(32));
        $this->entityManager->persist(new RefreshToken($user, self::hash($refresh), $now));
        $this->entityManager->flush();

        return [
            'accessToken' => $this->tokens->issue($user, $now),
            'refreshToken' => $refresh,
            'expiresIn' => $this->tokens->expiresIn(),
        ];
    }

    /**
     * Échange un jeton de renouvellement contre une nouvelle paire ; l'ancien est dépensé.
     *
     * @return array{accessToken: string, refreshToken: string, expiresIn: int}|null
     */
    public function refresh(#[\SensitiveParameter] string $refreshToken): ?array
    {
        $stored = $this->refreshTokens->findOneBy(['tokenHash' => self::hash($refreshToken)]);
        $now = $this->clock->now();
        if (null === $stored || !$stored->isUsable($now)) {
            return null;
        }
        $stored->revoke($now);

        return $this->open($stored->getUser());
    }

    public function close(#[\SensitiveParameter] string $refreshToken): void
    {
        $stored = $this->refreshTokens->findOneBy(['tokenHash' => self::hash($refreshToken)]);
        $stored?->revoke($this->clock->now());
        $this->entityManager->flush();
    }

    public static function hash(string $secret): string
    {
        return hash('sha256', $secret);
    }
}
