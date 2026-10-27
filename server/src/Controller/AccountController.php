<?php

declare(strict_types=1);

namespace App\Controller;

use App\Entity\User;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Component\Security\Http\Attribute\CurrentUser;

#[Route('/api/me')]
final class AccountController
{
    #[Route('', methods: ['GET'])]
    public function me(#[CurrentUser] User $user): JsonResponse
    {
        return new JsonResponse(self::describe($user));
    }

    /**
     * Suppression du compte et de toutes ses sauvegardes (exigée par l'App Store).
     * Les tournois restent sur l'iPhone : seule la copie en ligne disparaît.
     */
    #[Route('', methods: ['DELETE'])]
    public function delete(#[CurrentUser] User $user, EntityManagerInterface $entityManager): Response
    {
        $entityManager->remove($user);
        $entityManager->flush();

        return new Response(null, Response::HTTP_NO_CONTENT);
    }

    /** @return array<string, mixed> */
    public static function describe(User $user): array
    {
        return [
            'id' => (string) $user->getId(),
            'displayName' => $user->getDisplayName(),
            'email' => $user->getEmail(),
            'providers' => $user->providers(),
            'createdAt' => $user->getCreatedAt()->format(\DATE_ATOM),
        ];
    }
}
