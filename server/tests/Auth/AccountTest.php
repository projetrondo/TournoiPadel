<?php

declare(strict_types=1);

namespace App\Tests\Auth;

use App\Tests\Support\ApiTestCase;

final class AccountTest extends ApiTestCase
{
    public function testRefreshRotatesTheTokenAndLogoutRevokesIt(): void
    {
        $tokens = $this->tokensFor($this->account());
        $renewed = $this->json('POST', '/auth/refresh', ['refreshToken' => $tokens['refreshToken']]);
        self::assertSame(200, $this->responseStatus());
        self::assertNotSame($tokens['refreshToken'], $renewed['refreshToken']);

        // L'ancien jeton de renouvellement ne sert plus.
        $this->json('POST', '/auth/refresh', ['refreshToken' => $tokens['refreshToken']]);
        self::assertSame(401, $this->responseStatus());

        $this->json('POST', '/auth/logout', ['refreshToken' => $renewed['refreshToken']]);
        self::assertSame(204, $this->responseStatus());
        $this->json('POST', '/auth/refresh', ['refreshToken' => $renewed['refreshToken']]);
        self::assertSame(401, $this->responseStatus());
    }

    public function testDeletingTheAccountRemovesItsBackups(): void
    {
        $tokens = $this->tokensFor($this->account());
        $this->json('PUT', '/api/documents/session/5e55e55e-0000-4000-8000-000000000001', [
            'revision' => 1,
            'payload' => ['id' => '5E55E55E-0000-4000-8000-000000000001', 'name' => 'Jeudi'],
        ], $tokens['accessToken']);

        $this->json('DELETE', '/api/me', token: $tokens['accessToken']);
        self::assertSame(204, $this->responseStatus());

        $connection = $this->entityManager()->getConnection();
        self::assertSame(0, (int) $connection->fetchOne('SELECT COUNT(*) FROM synced_document'));
        self::assertSame(0, (int) $connection->fetchOne('SELECT COUNT(*) FROM account'));
        $this->json('GET', '/api/me', token: $tokens['accessToken']);
        self::assertSame(401, $this->responseStatus());
        $this->json('POST', '/auth/refresh', ['refreshToken' => $tokens['refreshToken']]);
        self::assertSame(401, $this->responseStatus());
    }

    public function testHealthCheck(): void
    {
        self::assertSame(['status' => 'ok'], $this->json('GET', '/health'));
    }

    public function testErrorsAreJson(): void
    {
        $response = $this->json('POST', '/auth/refresh', null);
        self::assertSame(400, $this->responseStatus());
        self::assertArrayHasKey('error', $response);
    }
}
