<?php

declare(strict_types=1);

namespace App\Tests\Auth;

use App\Auth\AppleIdentityVerifier;
use App\Tests\Support\ApiTestCase;
use App\Tests\Support\ProviderStub;
use PHPUnit\Framework\Attributes\DataProvider;

/**
 * « Se connecter avec Apple » : jetons signés par une clé de test, publiée par le faux Apple.
 */
final class AppleSignInTest extends ApiTestCase
{
    private \OpenSSLAsymmetricKey $key;

    protected function setUp(): void
    {
        parent::setUp();
        $key = openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => \OPENSSL_KEYTYPE_RSA]);
        self::assertNotFalse($key);
        $this->key = $key;
        $details = openssl_pkey_get_details($key);
        ProviderStub::$appleKeys = [[
            'kty' => 'RSA', 'kid' => 'cle-test', 'use' => 'sig', 'alg' => 'RS256',
            'n' => self::b64($details['rsa']['n']), 'e' => self::b64($details['rsa']['e']),
        ]];
    }

    private static function b64(string $raw): string
    {
        return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
    }

    /** @param array<string, mixed> $overrides */
    private function token(string $nonce, array $overrides = [], string $kid = 'cle-test'): string
    {
        $claims = $overrides + [
            'iss' => 'https://appleid.apple.com',
            'aud' => 'com.projetrondo.padelbuddy',
            'exp' => time() + 600,
            'iat' => time(),
            'sub' => '001234.apple.abcdef',
            'nonce' => hash('sha256', $nonce),
            'email' => 'abc@privaterelay.appleid.com',
            'email_verified' => 'true',
        ];
        $data = self::b64(json_encode(['alg' => 'RS256', 'kid' => $kid])).'.'.self::b64(json_encode($claims));
        openssl_sign($data, $signature, $this->key, \OPENSSL_ALGO_SHA256);

        return $data.'.'.self::b64($signature);
    }

    public function testValidTokenOpensSessionAndKeepsFirstName(): void
    {
        $tokens = $this->json('POST', '/auth/apple', ['identityToken' => $this->token('n1'), 'nonce' => 'n1', 'name' => 'Max']);
        self::assertSame(200, $this->responseStatus());
        self::assertSame('Max', $tokens['account']['displayName']);
        self::assertSame(['apple'], $tokens['account']['providers']);

        // Apple ne redonne pas le nom aux connexions suivantes : il est conservé.
        $again = $this->json('POST', '/auth/apple', ['identityToken' => $this->token('n2'), 'nonce' => 'n2']);
        self::assertSame($tokens['account']['id'], $again['account']['id']);
        self::assertSame('Max', $again['account']['displayName']);
    }

    /** @return iterable<string, array{array<string, mixed>, string}> */
    public static function invalidTokens(): iterable
    {
        yield 'autre application' => [['aud' => 'com.autre.app'], 'n'];
        yield 'expiré' => [['exp' => time() - 3600], 'n'];
        yield 'autre émetteur' => [['iss' => 'https://faux.example'], 'n'];
        yield 'nonce différent' => [[], 'un-autre-nonce'];
    }

    /** @param array<string, mixed> $overrides */
    #[DataProvider('invalidTokens')]
    public function testInvalidTokensAreRefused(array $overrides, string $sentNonce): void
    {
        $this->json('POST', '/auth/apple', ['identityToken' => $this->token('n', $overrides), 'nonce' => $sentNonce]);
        self::assertSame(401, $this->responseStatus());
    }

    public function testForgedSignatureIsRefused(): void
    {
        [$header, , $signature] = explode('.', $this->token('n'));
        $forged = self::b64(json_encode(['iss' => 'https://appleid.apple.com', 'aud' => 'com.projetrondo.padelbuddy', 'exp' => time() + 600, 'sub' => 'victime', 'nonce' => hash('sha256', 'n')]));
        $this->json('POST', '/auth/apple', ['identityToken' => $header.'.'.$forged.'.'.$signature, 'nonce' => 'n']);
        self::assertSame(401, $this->responseStatus());
    }

    public function testUnknownKeyIsRefused(): void
    {
        $this->json('POST', '/auth/apple', ['identityToken' => $this->token('n', kid: 'cle-inconnue'), 'nonce' => 'n']);
        self::assertSame(401, $this->responseStatus());
    }

    public function testPemConversionMatchesOpenSsl(): void
    {
        $details = openssl_pkey_get_details($this->key);
        $pem = AppleIdentityVerifier::rsaPem($details['rsa']['n'], $details['rsa']['e']);
        self::assertSame(trim($details['key']), trim($pem));
    }
}
