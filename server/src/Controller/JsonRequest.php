<?php

declare(strict_types=1);

namespace App\Controller;

use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpKernel\Exception\BadRequestHttpException;

/** Lecture du corps JSON et réponses d'erreur homogènes : `{"error": "…"}`. */
trait JsonRequest
{
    /** @return array<string, mixed> */
    private static function body(Request $request): array
    {
        try {
            $data = json_decode($request->getContent(), true, 64, \JSON_THROW_ON_ERROR);
        } catch (\JsonException) {
            throw new BadRequestHttpException('Corps JSON invalide.');
        }
        if (!\is_array($data)) {
            throw new BadRequestHttpException('Corps JSON invalide.');
        }

        return $data;
    }

    /** @param array<string, mixed> $body */
    private static function string(array $body, string $key): string
    {
        $value = $body[$key] ?? null;
        if (!\is_string($value) || '' === $value || \strlen($value) > 4096) {
            throw new BadRequestHttpException(\sprintf('Champ « %s » manquant.', $key));
        }

        return $value;
    }

    private static function error(string $message, int $status): JsonResponse
    {
        return new JsonResponse(['error' => $message], $status);
    }
}
