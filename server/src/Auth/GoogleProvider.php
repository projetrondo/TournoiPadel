<?php

declare(strict_types=1);

namespace App\Auth;

use Psr\Log\LoggerInterface;
use Symfony\Contracts\HttpClient\Exception\ExceptionInterface;
use Symfony\Contracts\HttpClient\HttpClientInterface;

/**
 * Connexion avec Google (OpenID Connect), sur le même principe que Rondo :
 * l'échange du code se fait de serveur à serveur, **le secret client reste au serveur**.
 */
final readonly class GoogleProvider
{
    private const string AUTHORIZATION_ENDPOINT = 'https://accounts.google.com/o/oauth2/v2/auth';
    private const string TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';
    private const string USERINFO_ENDPOINT = 'https://openidconnect.googleapis.com/v1/userinfo';

    public function __construct(
        private HttpClientInterface $http,
        private LoggerInterface $logger,
        #[\SensitiveParameter]
        private string $clientId,
        #[\SensitiveParameter]
        private string $clientSecret,
    ) {
    }

    /** Sans identifiants, le bouton n'est pas proposé (mieux qu'un bouton qui mène à une erreur). */
    public function isConfigured(): bool
    {
        return '' !== $this->clientId && '' !== $this->clientSecret;
    }

    public function authorizationUrl(string $state, string $redirectUri): string
    {
        return self::AUTHORIZATION_ENDPOINT.'?'.http_build_query([
            'client_id' => $this->clientId,
            'redirect_uri' => $redirectUri,
            'response_type' => 'code',
            // Au strict nécessaire : identité, adresse, prénom.
            'scope' => 'openid email profile',
            'state' => $state,
            'prompt' => 'select_account',
        ]);
    }

    /** @throws AuthFailed */
    public function exchange(string $code, string $redirectUri): ProviderIdentity
    {
        if (!$this->isConfigured()) {
            throw new AuthFailed('La connexion avec Google n\'est pas configurée.');
        }

        $token = $this->request('POST', self::TOKEN_ENDPOINT, ['body' => [
            'client_id' => $this->clientId,
            'client_secret' => $this->clientSecret,
            'code' => $code,
            'grant_type' => 'authorization_code',
            'redirect_uri' => $redirectUri,
        ]]);
        $accessToken = $token['access_token'] ?? null;
        if (!\is_string($accessToken) || '' === $accessToken) {
            throw new AuthFailed('Google n\'a pas confirmé votre identité. Réessayez.');
        }

        $profile = $this->request('GET', self::USERINFO_ENDPOINT, ['headers' => ['Authorization' => 'Bearer '.$accessToken]]);
        $subject = $profile['sub'] ?? null;
        if (!\is_string($subject) || '' === $subject) {
            throw new AuthFailed('Google n\'a pas transmis votre identité. Réessayez.');
        }
        $email = \is_string($profile['email'] ?? null) && true === ($profile['email_verified'] ?? false) ? $profile['email'] : null;
        $name = \is_string($profile['given_name'] ?? null) ? $profile['given_name'] : (\is_string($profile['name'] ?? null) ? $profile['name'] : null);

        return new ProviderIdentity(ProviderIdentity::GOOGLE, $subject, $email, $name);
    }

    /**
     * @param array<string, mixed> $options
     *
     * @return array<string, mixed>
     */
    private function request(string $method, string $url, array $options): array
    {
        try {
            $options['headers'] = ($options['headers'] ?? []) + ['Accept' => 'application/json'];
            $options['timeout'] = 10;

            /** @var array<string, mixed> */
            return $this->http->request($method, $url, $options)->toArray(false);
        } catch (ExceptionInterface $exception) {
            $this->logger->error('Échange refusé par Google.', ['exception' => $exception->getMessage()]);

            throw new AuthFailed('Google n\'a pas répondu. Réessayez dans un instant.', previous: $exception);
        }
    }
}
