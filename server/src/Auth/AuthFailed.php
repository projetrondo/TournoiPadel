<?php

declare(strict_types=1);

namespace App\Auth;

/** Connexion refusée ; le message est destiné à l'utilisateur. */
final class AuthFailed extends \RuntimeException
{
}
