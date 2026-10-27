<?php

declare(strict_types=1);

namespace App\Tests\Sync;

use App\Tests\Support\ApiTestCase;

/**
 * Sauvegarde en ligne des sessions et tournois.
 */
final class SyncTest extends ApiTestCase
{
    private const string TOURNAMENT = '7b4e5c1a-2f3d-4e5f-8a9b-0c1d2e3f4a5b';
    private const string SESSION = '5e55e55e-0000-4000-8000-000000000001';

    private string $token;

    protected function setUp(): void
    {
        parent::setUp();
        $this->token = $this->tokensFor($this->account())['accessToken'];
    }

    /** @return array<string, mixed> */
    private function put(string $kind, string $id, int $revision, string $name, ?string $token = null): array
    {
        return $this->json('PUT', "/api/documents/$kind/$id", [
            'revision' => $revision,
            'payload' => ['id' => strtoupper($id), 'name' => $name, 'revision' => $revision, 'schemaVersion' => 1],
        ], $token ?? $this->token);
    }

    public function testSavedDocumentsAreListedWithTheirContent(): void
    {
        $saved = $this->put('tournament', self::TOURNAMENT, 1, 'Jeudi');
        self::assertSame(200, $this->responseStatus());
        self::assertSame('saved', $saved['outcome']);
        $this->put('session', self::SESSION, 3, 'Les Aigles');

        $changes = $this->json('GET', '/api/sync?since=0', token: $this->token);
        self::assertSame(['tournament', 'session'], array_column($changes['documents'], 'kind'));
        self::assertSame('Jeudi', $changes['documents'][0]['payload']['name']);
        self::assertFalse($changes['hasMore']);

        // Rien de nouveau depuis le curseur.
        $again = $this->json('GET', '/api/sync?since='.$changes['cursor'], token: $this->token);
        self::assertSame([], $again['documents']);
        self::assertSame($changes['cursor'], $again['cursor']);
    }

    public function testNewerRevisionReplacesAndOlderIsRefusedWithTheCurrentVersion(): void
    {
        $this->put('tournament', self::TOURNAMENT, 2, 'Version 2');
        $this->put('tournament', self::TOURNAMENT, 5, 'Version 5');
        self::assertSame(200, $this->responseStatus());

        $conflict = $this->put('tournament', self::TOURNAMENT, 4, 'Vieille version hors ligne');
        self::assertSame(409, $this->responseStatus());
        self::assertSame('Version 5', $conflict['document']['payload']['name']);
        self::assertSame(5, $conflict['document']['revision']);

        $changes = $this->json('GET', '/api/sync?since=0', token: $this->token);
        self::assertCount(1, $changes['documents']);
        self::assertSame('Version 5', $changes['documents'][0]['payload']['name']);
    }

    public function testResendingTheSameVersionIsHarmless(): void
    {
        $first = $this->put('tournament', self::TOURNAMENT, 3, 'Jeudi');
        $second = $this->put('tournament', self::TOURNAMENT, 3, 'Jeudi');
        self::assertSame(200, $this->responseStatus());
        self::assertSame('unchanged', $second['outcome']);
        self::assertSame($first['document']['sequence'], $second['document']['sequence']);
    }

    public function testDeletionIsPropagatedAsATrace(): void
    {
        $this->put('tournament', self::TOURNAMENT, 1, 'Jeudi');
        $cursor = $this->json('GET', '/api/sync?since=0', token: $this->token)['cursor'];

        $this->json('DELETE', '/api/documents/tournament/'.self::TOURNAMENT.'?revision=2', token: $this->token);
        self::assertSame(204, $this->responseStatus());

        $changes = $this->json('GET', "/api/sync?since=$cursor", token: $this->token);
        self::assertCount(1, $changes['documents']);
        self::assertTrue($changes['documents'][0]['deleted']);
        self::assertNull($changes['documents'][0]['payload']);
    }

    public function testAccountsAreIsolated(): void
    {
        $this->put('tournament', self::TOURNAMENT, 1, 'Privé');
        $other = $this->tokensFor($this->account('google-autre'))['accessToken'];

        self::assertSame([], $this->json('GET', '/api/sync?since=0', token: $other)['documents']);
        // Même identifiant de document chez un autre compte : document distinct, rien n'est écrasé.
        $this->put('tournament', self::TOURNAMENT, 1, 'Autre compte', $other);
        self::assertSame(200, $this->responseStatus());
        $mine = $this->json('GET', '/api/sync?since=0', token: $this->token)['documents'];
        self::assertSame('Privé', $mine[0]['payload']['name']);
    }

    public function testInvalidDocumentsAreRefused(): void
    {
        $this->json('PUT', '/api/documents/tournament/'.self::TOURNAMENT, ['revision' => 1, 'payload' => ['id' => self::SESSION]], $this->token);
        self::assertSame(422, $this->responseStatus(), 'identifiant différent');
        $this->put('photo', self::TOURNAMENT, 1, 'x');
        self::assertSame(422, $this->responseStatus(), 'type inconnu');
        $this->put('tournament', self::TOURNAMENT, 0, 'x');
        self::assertSame(422, $this->responseStatus(), 'révision');
        $this->json('PUT', '/api/documents/tournament/'.self::TOURNAMENT, ['revision' => '1', 'payload' => 'texte'], $this->token);
        self::assertSame(400, $this->responseStatus());
    }

    public function testAuthenticationIsRequired(): void
    {
        $this->json('GET', '/api/sync?since=0');
        self::assertSame(401, $this->responseStatus());
        $this->json('GET', '/api/sync?since=0', token: 'jeton.invente.xyz');
        self::assertSame(401, $this->responseStatus());
    }

    public function testPaginationFollowsTheCursor(): void
    {
        for ($i = 1; $i <= 5; ++$i) {
            $this->put('tournament', \sprintf('00000000-0000-4000-8000-%012d', $i), 1, "T$i");
        }
        $names = [];
        $cursor = 0;
        do {
            $page = $this->json('GET', "/api/sync?since=$cursor&limit=2", token: $this->token);
            $names = [...$names, ...array_map(fn ($d) => $d['payload']['name'], $page['documents'])];
            $cursor = $page['cursor'];
        } while ($page['hasMore']);
        self::assertSame(['T1', 'T2', 'T3', 'T4', 'T5'], $names);
    }
}
