<?php

declare(strict_types=1);

namespace App\Entity;

use App\Repository\SyncedDocumentRepository;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Component\Uid\Uuid;

/**
 * Une session ou un tournoi sauvegardé, tel que l'app l'a envoyé (JSON opaque pour l'API).
 *
 * - `revision` est celle de l'app : une version n'est acceptée que si elle est plus récente
 *   que celle enregistrée, jamais une version plus ancienne n'en écrase une plus récente ;
 * - `sequence` est un compteur du serveur, croissant à chaque écriture : l'app demande
 *   « tout ce qui a changé depuis le numéro N » ;
 * - une suppression laisse une trace (`deletedAt`) pour que les autres appareils l'apprennent.
 */
#[ORM\Entity(repositoryClass: SyncedDocumentRepository::class)]
#[ORM\UniqueConstraint(name: 'document_per_account', columns: ['account_id', 'kind', 'document_id'])]
#[ORM\Index(name: 'document_changes', columns: ['account_id', 'sequence'])]
class SyncedDocument
{
    public const string SESSION = 'session';
    public const string TOURNAMENT = 'tournament';
    public const array KINDS = [self::SESSION, self::TOURNAMENT];

    #[ORM\Id]
    #[ORM\GeneratedValue]
    #[ORM\Column]
    private ?int $id = null;

    #[ORM\ManyToOne]
    #[ORM\JoinColumn(name: 'account_id', nullable: false, onDelete: 'CASCADE')]
    private User $user;

    #[ORM\Column(length: 16)]
    private string $kind;

    #[ORM\Column(type: 'uuid')]
    private Uuid $documentId;

    #[ORM\Column]
    private int $revision;

    /** JSON envoyé par l'app ; null une fois supprimé. */
    #[ORM\Column(type: 'text', nullable: true)]
    private ?string $payload;

    #[ORM\Column(type: 'bigint')]
    private string $sequence = '0';

    #[ORM\Column]
    private \DateTimeImmutable $updatedAt;

    #[ORM\Column(nullable: true)]
    private ?\DateTimeImmutable $deletedAt = null;

    public function __construct(User $user, string $kind, Uuid $documentId, int $revision, string $payload, \DateTimeImmutable $now)
    {
        $this->user = $user;
        $this->kind = $kind;
        $this->documentId = $documentId;
        $this->revision = $revision;
        $this->payload = $payload;
        $this->updatedAt = $now;
    }

    public function replace(int $revision, string $payload, \DateTimeImmutable $now): void
    {
        $this->revision = $revision;
        $this->payload = $payload;
        $this->deletedAt = null;
        $this->updatedAt = $now;
    }

    public function markDeleted(int $revision, \DateTimeImmutable $now): void
    {
        $this->revision = $revision;
        $this->payload = null;
        $this->deletedAt = $now;
        $this->updatedAt = $now;
    }

    public function assignSequence(int $sequence): void
    {
        $this->sequence = (string) $sequence;
    }

    public function getKind(): string
    {
        return $this->kind;
    }

    public function getDocumentId(): Uuid
    {
        return $this->documentId;
    }

    public function getRevision(): int
    {
        return $this->revision;
    }

    public function getPayload(): ?string
    {
        return $this->payload;
    }

    public function getSequence(): int
    {
        return (int) $this->sequence;
    }

    public function isDeleted(): bool
    {
        return null !== $this->deletedAt;
    }

    public function getUpdatedAt(): \DateTimeImmutable
    {
        return $this->updatedAt;
    }
}
