<?php

declare(strict_types=1);

namespace App\Tests\Security;

use App\Auth\ProviderIdentity;
use App\Entity\User;
use App\Security\InvalidToken;
use App\Security\TokenIssuer;
use PHPUnit\Framework\TestCase;

final class TokenIssuerTest extends TestCase
{
    private function user(): User
    {
        return User::fromIdentity(new ProviderIdentity(ProviderIdentity::GOOGLE, 'sub', null, null), new \DateTimeImmutable());
    }

    public function testIssuedTokenIsVerified(): void
    {
        $issuer = new TokenIssuer('secret');
        $user = $this->user();
        self::assertSame((string) $user->getId(), $issuer->verify($issuer->issue($user)));
    }

    public function testExpiredTokenIsRefused(): void
    {
        $issuer = new TokenIssuer('secret');
        $token = $issuer->issue($this->user(), new \DateTimeImmutable('-1 hour'));
        $this->expectException(InvalidToken::class);
        $issuer->verify($token);
    }

    public function testTokenSignedWithAnotherSecretIsRefused(): void
    {
        $token = (new TokenIssuer('autre'))->issue($this->user());
        $this->expectException(InvalidToken::class);
        (new TokenIssuer('secret'))->verify($token);
    }

    public function testTamperedTokenIsRefused(): void
    {
        $issuer = new TokenIssuer('secret');
        [$header, , $signature] = explode('.', $issuer->issue($this->user()));
        $payload = rtrim(strtr(base64_encode(json_encode(['iss' => 'eagle', 'sub' => 'quelqu-un', 'exp' => time() + 900])), '+/', '-_'), '=');
        $this->expectException(InvalidToken::class);
        $issuer->verify($header.'.'.$payload.'.'.$signature);
    }
}
