<?php

declare(strict_types=1);

namespace App\Tests\Security;

use App\Security\TokenIssuer;
use PHPUnit\Framework\TestCase;

final class ProductionSecretTest extends TestCase
{
    public function testDevelopmentSecretIsRefusedInProduction(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        new TokenIssuer('change-me-dev-only-token', 'prod');
    }

    public function testDevelopmentSecretIsAcceptedInDevelopment(): void
    {
        self::assertInstanceOf(TokenIssuer::class, new TokenIssuer('change-me-dev-only-token', 'dev'));
    }
}
