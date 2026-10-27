<?php

declare(strict_types=1);

namespace App\Entity;

use App\Repository\RefreshTokenRepository;
use Doctrine\ORM\Mapping as ORM;

/**
 * Jeton de renouvellement : longue durée, conservé haché, révocable et à usage unique
 * (chaque renouvellement en émet un nouveau et dépense l'ancien).
 */
#[ORM\Entity(repositoryClass: RefreshTokenRepository::class)]
#[ORM\Index(columns: ['account_id'])]
class RefreshToken
{
    public const int LIFETIME_DAYS = 90;

    #[ORM\Id]
    #[ORM\GeneratedValue]
    #[ORM\Column]
    private ?int $id = null;

    #[ORM\ManyToOne]
    #[ORM\JoinColumn(name: 'account_id', nullable: false, onDelete: 'CASCADE')]
    private User $user;

    #[ORM\Column(length: 64, unique: true)]
    private string $tokenHash;

    #[ORM\Column]
    private \DateTimeImmutable $expiresAt;

    #[ORM\Column(nullable: true)]
    private ?\DateTimeImmutable $revokedAt = null;

    public function __construct(User $user, string $tokenHash, \DateTimeImmutable $now)
    {
        $this->user = $user;
        $this->tokenHash = $tokenHash;
        $this->expiresAt = $now->modify(\sprintf('+%d days', self::LIFETIME_DAYS));
    }

    public function getUser(): User
    {
        return $this->user;
    }

    public function isUsable(\DateTimeImmutable $now): bool
    {
        return null === $this->revokedAt && $now < $this->expiresAt;
    }

    public function revoke(\DateTimeImmutable $now): void
    {
        $this->revokedAt ??= $now;
    }
}
