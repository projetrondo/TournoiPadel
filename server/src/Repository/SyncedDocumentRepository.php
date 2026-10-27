<?php

declare(strict_types=1);

namespace App\Repository;

use App\Entity\SyncedDocument;
use App\Entity\User;
use Doctrine\DBAL\LockMode;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;
use Symfony\Component\Uid\Uuid;

/** @extends ServiceEntityRepository<SyncedDocument> */
final class SyncedDocumentRepository extends ServiceEntityRepository
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, SyncedDocument::class);
    }

    /** Le document d'un compte, ligne verrouillée jusqu'à la fin de la transaction. */
    public function findOneForUpdate(User $user, string $kind, Uuid $id): ?SyncedDocument
    {
        /** @var SyncedDocument|null */
        return $this->createQueryBuilder('d')
            ->where('d.user = :user')
            ->andWhere('d.kind = :kind')
            ->andWhere('d.documentId = :id')
            ->setParameter('user', $user)
            ->setParameter('kind', $kind)
            ->setParameter('id', $id, 'uuid')
            ->getQuery()
            ->setLockMode(LockMode::PESSIMISTIC_WRITE)
            ->getOneOrNullResult();
    }

    /**
     * Documents modifiés après le numéro `since`, dans l'ordre.
     *
     * @return list<SyncedDocument>
     */
    public function changedSince(User $user, int $since, int $limit): array
    {
        /** @var list<SyncedDocument> */
        return $this->createQueryBuilder('d')
            ->where('d.user = :user')
            ->andWhere('d.sequence > :since')
            ->setParameter('user', $user)
            ->setParameter('since', $since)
            ->orderBy('d.sequence', 'ASC')
            ->setMaxResults($limit)
            ->getQuery()
            ->getResult();
    }

    /** Prochain numéro de modification (séquence PostgreSQL, partagée par tous les comptes). */
    public function nextSequence(): int
    {
        return (int) $this->getEntityManager()->getConnection()->fetchOne("SELECT nextval('document_sequence')");
    }
}
