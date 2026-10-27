<?php

declare(strict_types=1);

namespace App\Entity;

use App\Repository\LoginAttemptRepository;
use Doctrine\ORM\Mapping as ORM;

/**
 * Une connexion Google en cours, de l'ouverture du navigateur au retour dans l'app.
 *
 * 1. L'app demande à démarrer et fournit le condensé d'un secret qu'elle garde (PKCE) ;
 *    on retient le condensé de l'état envoyé à Google.
 * 2. Google revient sur l'API avec l'état : l'API échange le code (le secret client ne
 *    quitte jamais le serveur), trouve ou crée le compte, puis renvoie l'app avec un
 *    **code de passage** à usage unique, valable deux minutes.
 * 3. L'app échange ce code de passage contre ses jetons, en prouvant qu'elle détient le
 *    secret du début. Une autre app qui intercepterait l'adresse de retour n'a pas ce secret.
 */
#[ORM\Entity(repositoryClass: LoginAttemptRepository::class)]
class LoginAttempt
{
    public const int STATE_LIFETIME_SECONDS = 600;
    public const int HANDOFF_LIFETIME_SECONDS = 120;

    #[ORM\Id]
    #[ORM\GeneratedValue]
    #[ORM\Column]
    private ?int $id = null;

    #[ORM\Column(length: 64, unique: true)]
    private string $stateHash;

    /** Condensé SHA-256 (base64url) du secret de l'app. */
    #[ORM\Column(length: 128)]
    private string $codeChallenge;

    #[ORM\Column]
    private \DateTimeImmutable $createdAt;

    #[ORM\Column(length: 64, unique: true, nullable: true)]
    private ?string $handoffHash = null;

    #[ORM\ManyToOne]
    #[ORM\JoinColumn(name: 'account_id', nullable: true, onDelete: 'CASCADE')]
    private ?User $user = null;

    #[ORM\Column(nullable: true)]
    private ?\DateTimeImmutable $handoffIssuedAt = null;

    #[ORM\Column(nullable: true)]
    private ?\DateTimeImmutable $spentAt = null;

    public function __construct(string $stateHash, string $codeChallenge, \DateTimeImmutable $now)
    {
        $this->stateHash = $stateHash;
        $this->codeChallenge = $codeChallenge;
        $this->createdAt = $now;
    }

    public function isAwaitingProvider(\DateTimeImmutable $now): bool
    {
        return null === $this->handoffHash
            && null === $this->spentAt
            && $now->getTimestamp() - $this->createdAt->getTimestamp() <= self::STATE_LIFETIME_SECONDS;
    }

    public function issueHandoff(User $user, string $handoffHash, \DateTimeImmutable $now): void
    {
        $this->user = $user;
        $this->handoffHash = $handoffHash;
        $this->handoffIssuedAt = $now;
    }

    public function isHandoffUsable(\DateTimeImmutable $now): bool
    {
        return null !== $this->user
            && null !== $this->handoffIssuedAt
            && null === $this->spentAt
            && $now->getTimestamp() - $this->handoffIssuedAt->getTimestamp() <= self::HANDOFF_LIFETIME_SECONDS;
    }

    public function getCodeChallenge(): string
    {
        return $this->codeChallenge;
    }

    public function getUser(): ?User
    {
        return $this->user;
    }

    public function spend(\DateTimeImmutable $now): void
    {
        $this->spentAt ??= $now;
    }
}
