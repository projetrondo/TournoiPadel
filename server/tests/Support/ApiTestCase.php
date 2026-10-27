<?php

declare(strict_types=1);

namespace App\Tests\Support;

use App\Auth\AccountResolver;
use App\Auth\ProviderIdentity;
use App\Entity\User;
use App\Security\SessionManager;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Bundle\FrameworkBundle\KernelBrowser;
use Symfony\Bundle\FrameworkBundle\Test\WebTestCase;

/**
 * Base des tests d'API : vraie base PostgreSQL (`eagle_test`), vidée avant chaque test.
 */
abstract class ApiTestCase extends WebTestCase
{
    protected KernelBrowser $client;

    protected function setUp(): void
    {
        parent::setUp();
        $this->client = static::createClient();
        ProviderStub::reset();
        $connection = $this->entityManager()->getConnection();
        $connection->executeStatement('TRUNCATE synced_document, login_attempt, refresh_token, account RESTART IDENTITY CASCADE');
    }

    protected function entityManager(): EntityManagerInterface
    {
        /** @var EntityManagerInterface */
        return static::getContainer()->get(EntityManagerInterface::class);
    }

    protected function account(string $subject = 'google-123', string $provider = ProviderIdentity::GOOGLE): User
    {
        /** @var AccountResolver $resolver */
        $resolver = static::getContainer()->get(AccountResolver::class);

        return $resolver->resolve(new ProviderIdentity($provider, $subject, null, 'Joueur'));
    }

    /** @return array{accessToken: string, refreshToken: string, expiresIn: int} */
    protected function tokensFor(User $user): array
    {
        /** @var SessionManager $sessions */
        $sessions = static::getContainer()->get(SessionManager::class);

        return $sessions->open($user);
    }

    /**
     * @param array<string, mixed>|null $body
     *
     * @return array<string, mixed>
     */
    protected function json(string $method, string $uri, ?array $body = null, ?string $token = null): array
    {
        $headers = ['CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json'];
        if (null !== $token) {
            $headers['HTTP_AUTHORIZATION'] = 'Bearer '.$token;
        }
        $this->client->request($method, $uri, server: $headers, content: null === $body ? null : json_encode($body, \JSON_THROW_ON_ERROR));
        $content = $this->client->getResponse()->getContent();
        if (false === $content || '' === $content) {
            return [];
        }

        /** @var array<string, mixed> */
        return json_decode($content, true, 512, \JSON_THROW_ON_ERROR);
    }

    protected function responseStatus(): int
    {
        return $this->client->getResponse()->getStatusCode();
    }
}
