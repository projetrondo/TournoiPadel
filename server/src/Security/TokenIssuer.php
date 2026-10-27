<?php

declare(strict_types=1);

namespace App\Security;

use App\Entity\User;

/**
 * Émet et vérifie les jetons d'accès d'EAGLE (même mécanisme que Rondo).
 *
 * L'API est son propre émetteur : aucun fournisseur tiers entre l'app et
 * l'API. Le jeton est signé en HMAC-SHA256 — l'asymétrie n'a d'intérêt que
 * lorsqu'un tiers doit vérifier sans pouvoir signer, ce qui n'est le cas de
 * personne ici.
 *
 * Il est **court** — un quart d'heure — parce qu'il ne peut pas être révoqué :
 * une fois émis, il vaut jusqu'à son échéance. C'est le jeton de renouvellement,
 * lui révocable et conservé en base, qui porte la durée longue.
 *
 * Il ne porte que l'identifiant du compte, relu en base à chaque requête : un
 * compte supprimé n'est plus reconnu dès la requête suivante.
 */
final readonly class TokenIssuer
{
    public const string ISSUER = 'eagle';

    /** Durée de vie d'un jeton d'accès. Assez courte pour limiter le vol, assez longue pour ne pas rythmer la navigation. */
    private const int LIFETIME_SECONDS = 900;

    /** Tolérance d'horloge entre le serveur qui signe et celui qui vérifie. */
    private const int CLOCK_SKEW_SECONDS = 30;

    private string $key;

    public function __construct(#[\SensitiveParameter] string $secret, string $environment = 'prod')
    {
        if ('' === $secret) {
            throw new \InvalidArgumentException('La clé de signature des jetons est absente.');
        }
        // La valeur de développement de .env ne doit jamais signer de vrais jetons.
        if ('prod' === $environment && str_starts_with($secret, 'change-me')) {
            throw new \InvalidArgumentException('TOKEN_SECRET n\'est pas configuré pour la production.');
        }

        // Dérivée, et non utilisée telle quelle : la même valeur sert ailleurs
        // dans l'application, et deux usages d'un même secret ne doivent pas
        // partager la clé effective.
        $this->key = hash('sha256', 'eagle.access-token.'.$secret, true);
    }

    public function issue(User $user, ?\DateTimeImmutable $now = null): string
    {
        $now ??= new \DateTimeImmutable();
        $issuedAt = $now->getTimestamp();

        return $this->encode([
            'iss' => self::ISSUER,
            'sub' => (string) $user->getId(),
            'iat' => $issuedAt,
            'exp' => $issuedAt + self::LIFETIME_SECONDS,
        ]);
    }

    public function expiresIn(): int
    {
        return self::LIFETIME_SECONDS;
    }

    /**
     * Rend l'identifiant du compte, ou lève si le jeton ne vaut rien.
     *
     * @throws InvalidToken
     */
    public function verify(string $token, ?\DateTimeImmutable $now = null): string
    {
        $parts = explode('.', $token);

        if (3 !== \count($parts)) {
            throw new InvalidToken('Jeton illisible.');
        }

        [$header, $payload, $signature] = $parts;

        // Comparaison à temps constant : un test naïf laisse deviner la
        // signature octet par octet.
        if (!hash_equals($this->sign($header.'.'.$payload), $signature)) {
            throw new InvalidToken('Signature du jeton invalide.');
        }

        $claims = $this->decodeSegment($payload);
        $now ??= new \DateTimeImmutable();
        $timestamp = $now->getTimestamp();

        if (self::ISSUER !== ($claims['iss'] ?? null)) {
            throw new InvalidToken('Émetteur du jeton inattendu.');
        }

        $expiry = $claims['exp'] ?? null;

        if (!\is_int($expiry) || $timestamp > $expiry + self::CLOCK_SKEW_SECONDS) {
            throw new InvalidToken('Jeton expiré.');
        }

        $subject = $claims['sub'] ?? null;

        if (!\is_string($subject) || '' === $subject) {
            throw new InvalidToken('Jeton sans sujet exploitable.');
        }

        return $subject;
    }

    /**
     * @param array<string, mixed> $claims
     */
    private function encode(array $claims): string
    {
        $header = $this->encodeSegment(['alg' => 'HS256', 'typ' => 'JWT']);
        $payload = $this->encodeSegment($claims);

        return $header.'.'.$payload.'.'.$this->sign($header.'.'.$payload);
    }

    private function sign(string $data): string
    {
        return $this->base64UrlEncode(hash_hmac('sha256', $data, $this->key, true));
    }

    /**
     * @param array<string, mixed> $data
     */
    private function encodeSegment(array $data): string
    {
        return $this->base64UrlEncode(json_encode($data, \JSON_THROW_ON_ERROR | \JSON_UNESCAPED_SLASHES));
    }

    /**
     * @return array<string, mixed>
     */
    private function decodeSegment(string $segment): array
    {
        $json = base64_decode(strtr($segment, '-_', '+/'), true);

        if (false === $json) {
            throw new InvalidToken('Jeton illisible.');
        }

        try {
            /** @var array<string, mixed> $claims */
            $claims = json_decode($json, true, 512, \JSON_THROW_ON_ERROR);
        } catch (\JsonException) {
            throw new InvalidToken('Jeton illisible.');
        }

        return $claims;
    }

    private function base64UrlEncode(string $raw): string
    {
        return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
    }
}
