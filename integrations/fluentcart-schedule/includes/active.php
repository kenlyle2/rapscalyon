<?php
/**
 * Pure schedule logic: no WordPress calls, so it is tested with plain PHP.
 *
 * $cfg keys (all optional; an empty config means always active):
 *   days        int[]   0 Monday to 6 Sunday; empty = every day
 *   window      array   ['from' => 'HH:MM', 'to' => 'HH:MM'] or null; from > to crosses midnight and belongs to the starting day
 *   valid_from  string  YYYY-MM-DD, inclusive
 *   valid_until string  YYYY-MM-DD, inclusive of the whole day
 * Dates are judged on the day the window starts, in the given timezone.
 */
if (!function_exists('rsy_is_active')) {
    function rsy_is_active(array $cfg, int $now_ts, string $tz = 'UTC'): bool
    {
        $days  = array_values(array_filter((array) ($cfg['days'] ?? []), 'is_numeric'));
        $win   = $cfg['window'] ?? null;
        $from  = $cfg['valid_from'] ?? null;
        $until = $cfg['valid_until'] ?? null;
        if (!$days && !$win && !$from && !$until) {
            return true;
        }
        try {
            $zone = new DateTimeZone($tz);
        } catch (Exception $e) {
            $zone = new DateTimeZone('UTC');
        }
        $now = (new DateTimeImmutable('@' . $now_ts))->setTimezone($zone);
        $start = $now;
        if (is_array($win) && isset($win['from'], $win['to'])) {
            $mins = (int) $now->format('G') * 60 + (int) $now->format('i');
            $f = rsy_minutes($win['from']);
            $t = rsy_minutes($win['to']);
            if ($f === null || $t === null || $f === $t) {
                return false;
            }
            if ($f < $t) {
                if ($mins < $f || $mins >= $t) {
                    return false;
                }
            } elseif ($mins >= $f) {
                // evening part: starts today
            } elseif ($mins < $t) {
                $start = $now->modify('-1 day');
            } else {
                return false;
            }
        }
        if ($days && !in_array((int) $start->format('N') - 1, array_map('intval', $days), true)) {
            return false;
        }
        $date = $start->format('Y-m-d');
        if ($from && $date < $from) {
            return false;
        }
        if ($until && $date > $until) {
            return false;
        }
        return true;
    }

    function rsy_minutes($hhmm): ?int
    {
        if (!is_string($hhmm) || !preg_match('/^([01]\d|2[0-3]):([0-5]\d)$/', $hhmm, $m)) {
            return null;
        }
        return (int) $m[1] * 60 + (int) $m[2];
    }

    /** "Disponible los lunes y sábados de 17:00 a 22:00" for the notice shown to shoppers. */
    function rsy_label(array $cfg): string
    {
        static $plural = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábados', 'domingos'];
        $days = array_values(array_unique(array_map('intval', (array) ($cfg['days'] ?? []))));
        sort($days);
        $out = '';
        if ($days) {
            $list = array_map(function ($d) use ($plural) { return $plural[$d] ?? ''; }, $days);
            $last = array_pop($list);
            $out = 'los ' . ($list ? implode(', ', $list) . ' y ' : '') . $last;
        }
        $w = $cfg['window'] ?? null;
        if (is_array($w) && isset($w['from'], $w['to'])) {
            $out .= ($out ? ' ' : '') . 'de ' . $w['from'] . ' a ' . $w['to'];
        }
        if (!empty($cfg['valid_until'])) {
            $out .= ($out ? ', ' : '') . 'hasta el ' . $cfg['valid_until'];
        }
        return $out ? 'Disponible ' . $out : '';
    }
}
