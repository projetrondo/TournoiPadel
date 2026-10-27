<?php

declare(strict_types=1);

namespace App\Sync;

use App\Entity\SyncedDocument;

final readonly class SaveResult
{
    public const string SAVED = 'saved';
    /** Même révision, même contenu : renvoi sans effet (ex. après une coupure réseau). */
    public const string UNCHANGED = 'unchanged';
    /** Le serveur a une version au moins aussi récente : elle est renvoyée à l'app. */
    public const string CONFLICT = 'conflict';

    public function __construct(public string $outcome, public SyncedDocument $document)
    {
    }
}
