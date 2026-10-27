<?php

declare(strict_types=1);

namespace App\Auth;

use App\Entity\User;
use App\Repository\UserRepository;
use Doctrine\ORM\EntityManagerInterface;
use Psr\Clock\ClockInterface;

/**
 * Trouve le compte d'une identité, ou le crée à la première connexion.
 *
 * On ne rattache **jamais** deux fournisseurs par l'adresse : Apple peut masquer l'adresse,
 * et un rattachement automatique est exactement ce qu'exploiterait quelqu'un qui affiche
 * l'adresse d'autrui. Google et Apple donnent donc deux comptes distincts.
 */
final readonly class AccountResolver
{
    public function __construct(
        private UserRepository $users,
        private EntityManagerInterface $entityManager,
        private ClockInterface $clock,
    ) {
    }

    public function resolve(ProviderIdentity $identity): User
    {
        $now = $this->clock->now();
        $user = $this->users->findByIdentity($identity);
        if (null === $user) {
            $user = User::fromIdentity($identity, $now);
            $this->entityManager->persist($user);
        } else {
            $user->recordLogin($identity, $now);
        }
        $this->entityManager->flush();

        return $user;
    }
}
