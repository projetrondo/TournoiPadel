<?php

declare(strict_types=1);

namespace App\EventListener;

use Psr\Log\LoggerInterface;
use Symfony\Component\EventDispatcher\Attribute\AsEventListener;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpKernel\Event\ExceptionEvent;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;

/**
 * Toutes les erreurs en JSON (`{"error": "…"}`) : l'app n'a jamais à lire une page HTML.
 * Une erreur interne ne dévoile rien de son détail.
 */
#[AsEventListener(priority: -10)]
final readonly class JsonErrorListener
{
    public function __construct(private LoggerInterface $logger)
    {
    }

    public function __invoke(ExceptionEvent $event): void
    {
        $exception = $event->getThrowable();
        if ($exception instanceof HttpExceptionInterface) {
            $event->setResponse(new JsonResponse(
                ['error' => $exception->getMessage() ?: 'Requête refusée.'],
                $exception->getStatusCode(),
                $exception->getHeaders(),
            ));

            return;
        }
        $this->logger->error('Erreur interne.', ['exception' => $exception]);
        $event->setResponse(new JsonResponse(['error' => 'Erreur du serveur. Réessayez dans un instant.'], 500));
    }
}
