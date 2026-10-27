<?php

declare(strict_types=1);

namespace App\Auth;

use Psr\Clock\ClockInterface;
use Psr\Log\LoggerInterface;
use Symfony\Contracts\Cache\CacheInterface;
use Symfony\Contracts\Cache\ItemInterface;
use Symfony\Contracts\HttpClient\Exception\ExceptionInterface;
use Symfony\Contracts\HttpClient\HttpClientInterface;

/**
 * « Se connecter avec Apple » (obligatoire sur l'App Store dès qu'on propose Google).
 *
 * L'app reçoit d'Apple un jeton d'identité (JWT signé RS256) et nous le transmet. On vérifie
 * nous-mêmes, sans bibliothèque tierce :
 * - la signature, avec les clés publiques d'Apple (mises en cache une heure) ;
 * - l'émetteur (Apple), le public (notre app), l'échéance ;
 * - le `nonce` : l'app en a envoyé le condensé à Apple et nous donne l'original ; un jeton
 *   intercepté ne peut donc pas être rejoué depuis un autre appareil.
 */
final readonly class AppleIdentityVerifier
{
    public const string ISSUER = 'https://appleid.apple.com';
    public const string KEYS_URL = 'https://appleid.apple.com/auth/keys';

    public function __construct(
        private HttpClientInterface $http,
        private CacheInterface $cache,
        private ClockInterface $clock,
        private LoggerInterface $logger,
        private string $audience,
    ) {
    }

    /** @throws AuthFailed */
    public function verify(#[\SensitiveParameter] string $identityToken, #[\SensitiveParameter] string $nonce, ?string $name): ProviderIdentity
    {
        $parts = explode('.', $identityToken);
        if (3 !== \count($parts)) {
            throw new AuthFailed('Jeton Apple illisible.');
        }
        [$headerSegment, $payloadSegment, $signatureSegment] = $parts;
        $header = self::decodeJson($headerSegment);
        $claims = self::decodeJson($payloadSegment);
        $signature = self::base64UrlDecode($signatureSegment);

        if ('RS256' !== ($header['alg'] ?? null) || !\is_string($header['kid'] ?? null)) {
            throw new AuthFailed('Jeton Apple non pris en charge.');
        }
        $key = $this->publicKey($header['kid']);
        if (1 !== openssl_verify($headerSegment.'.'.$payloadSegment, $signature, $key, \OPENSSL_ALGO_SHA256)) {
            throw new AuthFailed('Signature du jeton Apple invalide.');
        }

        $now = $this->clock->now()->getTimestamp();
        if (self::ISSUER !== ($claims['iss'] ?? null)) {
            throw new AuthFailed('Jeton Apple d\'un autre émetteur.');
        }
        $audience = $claims['aud'] ?? null;
        if ($audience !== $this->audience && !(\is_array($audience) && \in_array($this->audience, $audience, true))) {
            throw new AuthFailed('Jeton Apple destiné à une autre application.');
        }
        if (!\is_int($claims['exp'] ?? null) || $now > $claims['exp'] + 30) {
            throw new AuthFailed('Jeton Apple expiré. Reconnectez-vous.');
        }
        if (!\is_string($claims['nonce'] ?? null) || !hash_equals($claims['nonce'], hash('sha256', $nonce))) {
            throw new AuthFailed('Jeton Apple non reconnu pour cette connexion.');
        }
        $subject = $claims['sub'] ?? null;
        if (!\is_string($subject) || '' === $subject) {
            throw new AuthFailed('Apple n\'a pas transmis votre identité.');
        }
        $verified = true === ($claims['email_verified'] ?? false) || 'true' === ($claims['email_verified'] ?? null);
        $email = $verified && \is_string($claims['email'] ?? null) ? $claims['email'] : null;
        $name = null !== $name && '' !== trim($name) ? mb_substr(trim($name), 0, 120) : null;

        return new ProviderIdentity(ProviderIdentity::APPLE, $subject, $email, $name);
    }

    private function publicKey(string $kid): \OpenSSLAsymmetricKey
    {
        $keys = $this->cache->get('apple_signing_keys', function (ItemInterface $item): array {
            $item->expiresAfter(3600);
            try {
                /** @var array{keys?: list<array<string, string>>} $set */
                $set = $this->http->request('GET', self::KEYS_URL, ['timeout' => 10])->toArray();
            } catch (ExceptionInterface $exception) {
                $this->logger->error('Clés Apple indisponibles.', ['exception' => $exception->getMessage()]);
                $item->expiresAfter(1);

                throw new AuthFailed('Apple n\'a pas répondu. Réessayez dans un instant.', previous: $exception);
            }

            return $set['keys'] ?? [];
        });

        foreach ($keys as $jwk) {
            if (($jwk['kid'] ?? null) === $kid && 'RSA' === ($jwk['kty'] ?? null)) {
                $key = openssl_pkey_get_public(self::rsaPem(self::base64UrlDecode($jwk['n']), self::base64UrlDecode($jwk['e'])));
                if (false !== $key) {
                    return $key;
                }
            }
        }

        throw new AuthFailed('Clé de signature Apple inconnue.');
    }

    /** Clé publique RSA (module, exposant) au format PEM, encodée en DER à la main. */
    public static function rsaPem(string $modulus, string $exponent): string
    {
        $integer = static function (string $bytes): string {
            // Entier DER positif : un octet nul devant si le bit de poids fort est à 1.
            if (\ord($bytes[0]) > 0x7F) {
                $bytes = "\x00".$bytes;
            }

            return "\x02".self::derLength(\strlen($bytes)).$bytes;
        };
        $body = $integer($modulus).$integer($exponent);
        $rsaKey = "\x30".self::derLength(\strlen($body)).$body;
        $algorithm = "\x30\x0D\x06\x09\x2A\x86\x48\x86\xF7\x0D\x01\x01\x01\x05\x00";
        $bitString = "\x03".self::derLength(\strlen($rsaKey) + 1)."\x00".$rsaKey;
        $spki = "\x30".self::derLength(\strlen($algorithm.$bitString)).$algorithm.$bitString;

        return "-----BEGIN PUBLIC KEY-----\n".chunk_split(base64_encode($spki), 64, "\n")."-----END PUBLIC KEY-----\n";
    }

    private static function derLength(int $length): string
    {
        if ($length < 0x80) {
            return \chr($length);
        }
        $bytes = ltrim(pack('N', $length), "\x00");

        return \chr(0x80 | \strlen($bytes)).$bytes;
    }

    /** @return array<string, mixed> */
    private static function decodeJson(string $segment): array
    {
        $decoded = json_decode(self::base64UrlDecode($segment), true);
        if (!\is_array($decoded)) {
            throw new AuthFailed('Jeton Apple illisible.');
        }

        return $decoded;
    }

    private static function base64UrlDecode(string $segment): string
    {
        $decoded = base64_decode(strtr($segment, '-_', '+/'), true);
        if (false === $decoded) {
            throw new AuthFailed('Jeton Apple illisible.');
        }

        return $decoded;
    }
}
