<?php

declare(strict_types=1);

namespace App\Repository;

use App\Auth\ProviderIdentity;
use App\Entity\User;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;

/** @extends ServiceEntityRepository<User> */
final class UserRepository extends ServiceEntityRepository
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, User::class);
    }

    public function findByIdentity(ProviderIdentity $identity): ?User
    {
        return match ($identity->provider) {
            ProviderIdentity::GOOGLE => $this->findOneBy(['googleSubject' => $identity->subject]),
            ProviderIdentity::APPLE => $this->findOneBy(['appleSubject' => $identity->subject]),
        };
    }
}
