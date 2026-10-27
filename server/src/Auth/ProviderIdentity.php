<?php

declare(strict_types=1);

namespace App\Auth;

/**
 * Ce qu'un fournisseur (Google, Apple) atteste de la personne qui se connecte.
 */
final readonly class ProviderIdentity
{
    public const string GOOGLE = 'google';
    public const string APPLE = 'apple';

    public function __construct(
        public string $provider,
        public string $subject,
        public ?string $email,
        public ?string $name,
    ) {
    }
}
