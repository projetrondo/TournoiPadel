<?php

declare(strict_types=1);

namespace App\Controller;

use Doctrine\DBAL\Connection;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Attribute\Route;

final class HealthController
{
    /** Sonde de supervision : l'API répond et la base aussi. */
    #[Route('/health', methods: ['GET'])]
    public function __invoke(Connection $connection): JsonResponse
    {
        $connection->fetchOne('SELECT 1');

        return new JsonResponse(['status' => 'ok']);
    }
}
