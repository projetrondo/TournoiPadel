<?php

declare(strict_types=1);

namespace App\Entity;

use App\Auth\ProviderIdentity;
use App\Repository\UserRepository;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Bridge\Doctrine\Types\UuidType;
use Symfony\Component\Security\Core\User\UserInterface;
use Symfony\Component\Uid\Uuid;

/**
 * Un compte EAGLE. Il n'a pas de mot de passe : on s'y connecte avec Google ou Apple.
 *
 * Le compte est rattaché à l'identifiant stable du fournisseur (`sub`), jamais à l'adresse :
 * une adresse change, se recycle, et Apple peut la masquer.
 */
#[ORM\Entity(repositoryClass: UserRepository::class)]
#[ORM\Table(name: 'account')]
class User implements UserInterface
{
    #[ORM\Id]
    #[ORM\Column(type: UuidType::NAME, unique: true)]
    private Uuid $id;

    #[ORM\Column(length: 255, unique: true, nullable: true)]
    private ?string $googleSubject = null;

    #[ORM\Column(length: 255, unique: true, nullable: true)]
    private ?string $appleSubject = null;

    #[ORM\Column(length: 320, nullable: true)]
    private ?string $email = null;

    #[ORM\Column(length: 120, nullable: true)]
    private ?string $displayName = null;

    #[ORM\Column]
    private \DateTimeImmutable $createdAt;

    #[ORM\Column]
    private \DateTimeImmutable $lastLoginAt;

    private function __construct(\DateTimeImmutable $now)
    {
        $this->id = Uuid::v7();
        $this->createdAt = $now;
        $this->lastLoginAt = $now;
    }

    public static function fromIdentity(ProviderIdentity $identity, \DateTimeImmutable $now): self
    {
        $user = new self($now);
        $user->attach($identity);
        $user->email = $identity->email;
        $user->displayName = $identity->name;

        return $user;
    }

    public function attach(ProviderIdentity $identity): void
    {
        match ($identity->provider) {
            ProviderIdentity::GOOGLE => $this->googleSubject = $identity->subject,
            ProviderIdentity::APPLE => $this->appleSubject = $identity->subject,
        };
    }

    public function recordLogin(ProviderIdentity $identity, \DateTimeImmutable $now): void
    {
        $this->lastLoginAt = $now;
        // Apple ne transmet le nom qu'à la première connexion : on ne l'efface jamais.
        $this->displayName ??= $identity->name;
        $this->email = $identity->email ?? $this->email;
    }

    public function getId(): Uuid
    {
        return $this->id;
    }

    public function getEmail(): ?string
    {
        return $this->email;
    }

    public function getDisplayName(): ?string
    {
        return $this->displayName;
    }

    public function getCreatedAt(): \DateTimeImmutable
    {
        return $this->createdAt;
    }

    /** @return list<string> */
    public function providers(): array
    {
        return array_values(array_filter([
            null !== $this->googleSubject ? ProviderIdentity::GOOGLE : null,
            null !== $this->appleSubject ? ProviderIdentity::APPLE : null,
        ]));
    }

    public function getUserIdentifier(): string
    {
        return (string) $this->id;
    }

    public function getRoles(): array
    {
        return ['ROLE_USER'];
    }

    public function eraseCredentials(): void
    {
    }
}
