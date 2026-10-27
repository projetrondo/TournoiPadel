<?php

declare(strict_types=1);

namespace App\Tests\Auth;

use App\Tests\Support\ApiTestCase;
use App\Tests\Support\ProviderStub;

/**
 * Parcours complet de la connexion Google depuis l'app, Google étant simulé.
 */
final class GoogleSignInTest extends ApiTestCase
{
    private const string VERIFIER = 'secret-de-l-app-0123456789-abcdefghijklmnopqrstuvwxyz';

    private static function challenge(string $verifier = self::VERIFIER): string
    {
        return rtrim(strtr(base64_encode(hash('sha256', $verifier, true)), '+/', '-_'), '=');
    }

    /** Démarre et rend l'état transmis à Google. */
    private function startSignIn(): string
    {
        $response = $this->json('POST', '/auth/google/start', ['codeChallenge' => self::challenge()]);
        self::assertSame(200, $this->responseStatus());
        $url = (string) $response['authorizationUrl'];
        self::assertStringStartsWith('https://accounts.google.com/o/oauth2/v2/auth?', $url);
        parse_str((string) parse_url($url, \PHP_URL_QUERY), $query);
        self::assertSame('https://api.eagle.test/auth/google/callback', $query['redirect_uri']);
        self::assertSame('openid email profile', $query['scope']);

        return (string) $query['state'];
    }

    /** @return array<string, string> paramètres de l'adresse de retour vers l'app */
    private function returnFromGoogle(string $query): array
    {
        $this->client->request('GET', '/auth/google/callback?'.$query);
        self::assertSame(302, $this->responseStatus());
        $location = (string) $this->client->getResponse()->headers->get('Location');
        self::assertStringStartsWith('eagle://auth?', $location);
        parse_str((string) parse_url($location, \PHP_URL_QUERY), $params);

        /** @var array<string, string> */
        return $params;
    }

    public function testFullSignInCreatesAccountAndOpensSession(): void
    {
        $state = $this->startSignIn();
        $params = $this->returnFromGoogle(http_build_query(['code' => ProviderStub::$validGoogleCode, 'state' => $state]));
        self::assertArrayHasKey('handoff', $params);

        $tokens = $this->json('POST', '/auth/google/redeem', ['handoff' => $params['handoff'], 'codeVerifier' => self::VERIFIER]);
        self::assertSame(200, $this->responseStatus());
        self::assertSame('Léa', $tokens['account']['displayName']);
        self::assertSame('lea@example.com', $tokens['account']['email']);
        self::assertSame(['google'], $tokens['account']['providers']);

        $me = $this->json('GET', '/api/me', token: (string) $tokens['accessToken']);
        self::assertSame(200, $this->responseStatus());
        self::assertSame($tokens['account']['id'], $me['id']);

        // Le secret client n'est envoyé qu'à Google, de serveur à serveur.
        $tokenRequest = array_values(array_filter(ProviderStub::$requests, fn ($r) => str_contains($r['url'], 'oauth2.googleapis.com/token')))[0];
        self::assertStringContainsString('client_secret=test-google-secret', $tokenRequest['body']);
    }

    public function testSecondSignInReusesTheSameAccount(): void
    {
        $ids = [];
        foreach ([1, 2] as $attempt) {
            $state = $this->startSignIn();
            $params = $this->returnFromGoogle(http_build_query(['code' => ProviderStub::$validGoogleCode, 'state' => $state]));
            $tokens = $this->json('POST', '/auth/google/redeem', ['handoff' => $params['handoff'], 'codeVerifier' => self::VERIFIER]);
            $ids[] = $tokens['account']['id'];
        }
        self::assertSame($ids[0], $ids[1]);
    }

    public function testHandoffWorksOnlyOnceAndOnlyWithTheVerifier(): void
    {
        $state = $this->startSignIn();
        $params = $this->returnFromGoogle(http_build_query(['code' => ProviderStub::$validGoogleCode, 'state' => $state]));

        $this->json('POST', '/auth/google/redeem', ['handoff' => $params['handoff'], 'codeVerifier' => 'un-autre-secret-qui-ne-correspond-a-rien-du-tout']);
        self::assertSame(401, $this->responseStatus());

        // Même avec le bon secret ensuite : le code de passage a été dépensé.
        $this->json('POST', '/auth/google/redeem', ['handoff' => $params['handoff'], 'codeVerifier' => self::VERIFIER]);
        self::assertSame(401, $this->responseStatus());
    }

    public function testUnknownStateIsRefused(): void
    {
        $params = $this->returnFromGoogle(http_build_query(['code' => ProviderStub::$validGoogleCode, 'state' => 'etat-invente']));
        self::assertArrayHasKey('error', $params);
        self::assertArrayNotHasKey('handoff', $params);
    }

    public function testStateCannotBeReplayed(): void
    {
        $state = $this->startSignIn();
        $this->returnFromGoogle(http_build_query(['code' => ProviderStub::$validGoogleCode, 'state' => $state]));
        $params = $this->returnFromGoogle(http_build_query(['code' => ProviderStub::$validGoogleCode, 'state' => $state]));
        self::assertArrayHasKey('error', $params);
    }

    public function testCancelledOrRefusedByGoogle(): void
    {
        $params = $this->returnFromGoogle(http_build_query(['error' => 'access_denied', 'state' => $this->startSignIn()]));
        self::assertSame('cancelled', $params['error']);

        $params = $this->returnFromGoogle(http_build_query(['code' => 'code-refuse', 'state' => $this->startSignIn()]));
        self::assertArrayHasKey('error', $params);
    }

    public function testInvalidChallengeIsRefused(): void
    {
        $this->json('POST', '/auth/google/start', ['codeChallenge' => 'trop-court']);
        self::assertSame(422, $this->responseStatus());
    }

    public function testProvidersAdvertiseGoogleWhenConfigured(): void
    {
        self::assertSame(['google' => true, 'apple' => true], $this->json('GET', '/auth/providers'));
    }
}
