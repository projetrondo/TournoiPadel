<?php

declare(strict_types=1);

namespace App\Controller;

use App\Entity\User;
use App\Sync\DocumentSync;
use App\Sync\InvalidDocument;
use App\Sync\SaveResult;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Component\Security\Http\Attribute\CurrentUser;
use Symfony\Component\Uid\Uuid;

/**
 * Sauvegarde en ligne :
 * - `GET /api/sync?since=N` : ce qui a changé depuis le curseur N (0 = tout) ;
 * - `PUT /api/documents/{kind}/{id}` `{revision, payload}` : envoie une version
 *   (200 enregistrée ou identique, 409 si le serveur en a une plus récente, renvoyée) ;
 * - `DELETE /api/documents/{kind}/{id}?revision=N` : supprime, en laissant une trace.
 */
final class SyncController
{
    use JsonRequest;

    public function __construct(private readonly DocumentSync $sync)
    {
    }

    #[Route('/api/sync', methods: ['GET'])]
    public function changes(#[CurrentUser] User $user, Request $request): JsonResponse
    {
        $changes = $this->sync->changes($user, $request->query->getInt('since'), $request->query->getInt('limit', 200));

        return new JsonResponse([
            'documents' => array_map(DocumentSync::describe(...), $changes['documents']),
            'cursor' => $changes['cursor'],
            'hasMore' => $changes['hasMore'],
        ]);
    }

    #[Route('/api/documents/{kind}/{id}', methods: ['PUT'], requirements: ['id' => '[0-9a-fA-F-]{36}'])]
    public function save(#[CurrentUser] User $user, string $kind, string $id, Request $request): JsonResponse
    {
        $body = self::body($request);
        $revision = $body['revision'] ?? null;
        $payload = $body['payload'] ?? null;
        if (!\is_int($revision) || !\is_array($payload) || !Uuid::isValid($id)) {
            return self::error('Document invalide.', Response::HTTP_BAD_REQUEST);
        }
        try {
            $result = $this->sync->save($user, $kind, Uuid::fromString($id), $revision, $payload);
        } catch (InvalidDocument $invalid) {
            return self::error($invalid->getMessage(), Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        return new JsonResponse(
            ['outcome' => $result->outcome, 'document' => DocumentSync::describe($result->document)],
            SaveResult::CONFLICT === $result->outcome ? Response::HTTP_CONFLICT : Response::HTTP_OK,
        );
    }

    #[Route('/api/documents/{kind}/{id}', methods: ['DELETE'], requirements: ['id' => '[0-9a-fA-F-]{36}'])]
    public function delete(#[CurrentUser] User $user, string $kind, string $id, Request $request): Response
    {
        if (!Uuid::isValid($id)) {
            return self::error('Document invalide.', Response::HTTP_BAD_REQUEST);
        }
        try {
            $this->sync->delete($user, $kind, Uuid::fromString($id), max(1, $request->query->getInt('revision', 1)));
        } catch (InvalidDocument $invalid) {
            return self::error($invalid->getMessage(), Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        return new Response(null, Response::HTTP_NO_CONTENT);
    }
}
