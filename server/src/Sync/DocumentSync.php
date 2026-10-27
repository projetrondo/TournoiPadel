<?php

declare(strict_types=1);

namespace App\Sync;

use App\Entity\SyncedDocument;
use App\Entity\User;
use App\Repository\SyncedDocumentRepository;
use Doctrine\ORM\EntityManagerInterface;
use Psr\Clock\ClockInterface;
use Symfony\Component\Uid\Uuid;

/**
 * Sauvegarde des sessions et tournois d'un compte, et diffusion des changements à ses
 * autres appareils.
 *
 * Règle unique, la même que le partage existant : **une version ne remplace que plus
 * ancienne qu'elle** (révision strictement supérieure). Un appareil resté hors ligne qui
 * renvoie une vieille version reçoit la version enregistrée, au lieu de l'écraser.
 */
final readonly class DocumentSync
{
    /** Taille maximale d'un document : un tournoi de 24 joueurs en fait une fraction. */
    public const int MAX_PAYLOAD_BYTES = 1_000_000;

    public function __construct(
        private SyncedDocumentRepository $documents,
        private EntityManagerInterface $entityManager,
        private ClockInterface $clock,
    ) {
    }

    /**
     * @param array<string, mixed> $payload
     *
     * @throws InvalidDocument
     */
    public function save(User $user, string $kind, Uuid $id, int $revision, array $payload): SaveResult
    {
        self::assertKind($kind);
        if ($revision < 1) {
            throw new InvalidDocument('Révision invalide.');
        }
        if (($payload['id'] ?? null) === null || !\is_string($payload['id']) || !Uuid::isValid($payload['id']) || !Uuid::fromString($payload['id'])->equals($id)) {
            throw new InvalidDocument('Le document ne correspond pas à son identifiant.');
        }
        $json = json_encode($payload, \JSON_THROW_ON_ERROR | \JSON_UNESCAPED_UNICODE | \JSON_UNESCAPED_SLASHES);
        if (\strlen($json) > self::MAX_PAYLOAD_BYTES) {
            throw new InvalidDocument('Document trop volumineux.');
        }

        return $this->entityManager->wrapInTransaction(function () use ($user, $kind, $id, $revision, $json): SaveResult {
            $now = $this->clock->now();
            $existing = $this->documents->findOneForUpdate($user, $kind, $id);
            if (null !== $existing) {
                if ($existing->getRevision() >= $revision) {
                    $identical = $existing->getRevision() === $revision && $existing->getPayload() === $json;

                    return new SaveResult($identical ? SaveResult::UNCHANGED : SaveResult::CONFLICT, $existing);
                }
                $existing->replace($revision, $json, $now);
                $document = $existing;
            } else {
                $document = new SyncedDocument($user, $kind, $id, $revision, $json, $now);
                $this->entityManager->persist($document);
            }
            $document->assignSequence($this->documents->nextSequence());
            $this->entityManager->flush();

            return new SaveResult(SaveResult::SAVED, $document);
        });
    }

    /** @throws InvalidDocument */
    public function delete(User $user, string $kind, Uuid $id, int $revision): void
    {
        self::assertKind($kind);
        $this->entityManager->wrapInTransaction(function () use ($user, $kind, $id, $revision): void {
            $existing = $this->documents->findOneForUpdate($user, $kind, $id);
            if (null === $existing || $existing->isDeleted()) {
                return;
            }
            $existing->markDeleted(max($existing->getRevision(), $revision), $this->clock->now());
            $existing->assignSequence($this->documents->nextSequence());
            $this->entityManager->flush();
        });
    }

    /** @return array{documents: list<SyncedDocument>, cursor: int, hasMore: bool} */
    public function changes(User $user, int $since, int $limit = 200): array
    {
        $limit = max(1, min($limit, 500));
        $documents = $this->documents->changedSince($user, max(0, $since), $limit + 1);
        $hasMore = \count($documents) > $limit;
        $documents = \array_slice($documents, 0, $limit);
        $cursor = [] === $documents ? max(0, $since) : $documents[array_key_last($documents)]->getSequence();

        return ['documents' => $documents, 'cursor' => $cursor, 'hasMore' => $hasMore];
    }

    /** @return array<string, mixed> */
    public static function describe(SyncedDocument $document): array
    {
        return [
            'kind' => $document->getKind(),
            'id' => $document->getDocumentId()->toRfc4122(),
            'revision' => $document->getRevision(),
            'deleted' => $document->isDeleted(),
            'payload' => null === $document->getPayload() ? null : json_decode($document->getPayload(), true),
            'updatedAt' => $document->getUpdatedAt()->format(\DATE_ATOM),
            'sequence' => $document->getSequence(),
        ];
    }

    private static function assertKind(string $kind): void
    {
        if (!\in_array($kind, SyncedDocument::KINDS, true)) {
            throw new InvalidDocument('Type de document inconnu.');
        }
    }
}
