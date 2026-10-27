<?php

declare(strict_types=1);

namespace App\Tests\Support;

use Symfony\Component\HttpClient\Response\MockResponse;
use Symfony\Contracts\HttpClient\ResponseInterface;

/**
 * Faux Google et faux Apple pour les tests : répond selon l'adresse appelée.
 */
final class ProviderStub
{
    /** Profil renvoyé par Google pour le prochain échange de code. @var array<string, mixed> */
    public static array $googleProfile = ['sub' => 'google-123', 'email' => 'lea@example.com', 'email_verified' => true, 'given_name' => 'Léa'];
    /** Code accepté par le faux Google. */
    public static string $validGoogleCode = 'code-google-valide';
    /** Clés publiques du faux Apple (JWKS). @var list<array<string, string>> */
    public static array $appleKeys = [];
    /** @var list<array{method: string, url: string, body: string}> */
    public static array $requests = [];

    public static function reset(): void
    {
        self::$googleProfile = ['sub' => 'google-123', 'email' => 'lea@example.com', 'email_verified' => true, 'given_name' => 'Léa'];
        self::$appleKeys = [];
        self::$requests = [];
    }

    /** @param array<string, mixed> $options */
    public function __invoke(string $method, string $url, array $options): ResponseInterface
    {
        $body = \is_string($options['body'] ?? null) ? $options['body'] : '';
        self::$requests[] = ['method' => $method, 'url' => $url, 'body' => $body];

        return match (true) {
            str_starts_with($url, 'https://oauth2.googleapis.com/token') => str_contains($body, 'code='.self::$validGoogleCode)
                ? self::json(['access_token' => 'jeton-google', 'token_type' => 'Bearer'])
                : self::json(['error' => 'invalid_grant'], 400),
            str_starts_with($url, 'https://openidconnect.googleapis.com/v1/userinfo') => self::json(self::$googleProfile),
            str_starts_with($url, 'https://appleid.apple.com/auth/keys') => self::json(['keys' => self::$appleKeys]),
            default => self::json(['error' => 'adresse inattendue : '.$url], 404),
        };
    }

    /** @param array<string, mixed> $data */
    private static function json(array $data, int $status = 200): MockResponse
    {
        return new MockResponse(json_encode($data, \JSON_THROW_ON_ERROR), [
            'http_code' => $status,
            'response_headers' => ['content-type' => 'application/json'],
        ]);
    }
}
