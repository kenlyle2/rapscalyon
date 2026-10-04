<?php
// Plain PHP tests for includes/active.php. Run: php tests/active_test.php
require __DIR__ . '/../includes/active.php';

$fail = 0;
function check($name, $got, $want) {
    global $fail;
    if ($got !== $want) { $fail++; echo "FAIL $name: got " . var_export($got, true) . "\n"; }
}
$cr = 'America/Costa_Rica'; // UTC-6, no DST
$t = function ($local) use ($cr) { return (new DateTimeImmutable($local, new DateTimeZone($cr)))->getTimestamp(); };

check('empty config is always active', rsy_is_active([], $t('2026-10-04 03:00')), true);
// 2026-09-28 is a Monday, 2026-09-29 a Tuesday
check('monday only: monday', rsy_is_active(['days' => [0]], $t('2026-09-28 12:00'), $cr), true);
check('monday only: tuesday', rsy_is_active(['days' => [0]], $t('2026-09-29 12:00'), $cr), false);
check('weekend', rsy_is_active(['days' => [5, 6]], $t('2026-10-03 12:00'), $cr), true);
check('weekend: friday', rsy_is_active(['days' => [5, 6]], $t('2026-10-02 12:00'), $cr), false);
// timezone, not the server's: Monday 23:30 in Costa Rica is already Tuesday 05:30 UTC
check('store timezone wins (monday 23:30 CR)', rsy_is_active(['days' => [0]], $t('2026-09-28 23:30'), $cr), true);
check('same instant judged in UTC is tuesday', rsy_is_active(['days' => [0]], $t('2026-09-28 23:30'), 'UTC'), false);
$win = ['days' => [0], 'window' => ['from' => '17:00', 'to' => '22:00']];
check('window inside', rsy_is_active($win, $t('2026-09-28 18:00'), $cr), true);
check('window before', rsy_is_active($win, $t('2026-09-28 16:59'), $cr), false);
check('window end is exclusive', rsy_is_active($win, $t('2026-09-28 22:00'), $cr), false);
// crossing midnight belongs to the starting day: Monday 22:00 to Tuesday 02:00
$night = ['days' => [0], 'window' => ['from' => '22:00', 'to' => '02:00']];
check('night: monday 23:00', rsy_is_active($night, $t('2026-09-28 23:00'), $cr), true);
check('night: tuesday 01:00 (still monday\'s)', rsy_is_active($night, $t('2026-09-29 01:00'), $cr), true);
check('night: tuesday 03:00', rsy_is_active($night, $t('2026-09-29 03:00'), $cr), false);
check('night: tuesday 23:00 (tuesday is not listed)', rsy_is_active($night, $t('2026-09-29 23:00'), $cr), false);
check('night: monday 01:00 belongs to sunday', rsy_is_active($night, $t('2026-09-28 01:00'), $cr), false);
check('until is inclusive of the whole day', rsy_is_active(['valid_until' => '2026-10-31'], $t('2026-10-31 23:59'), $cr), true);
check('after until', rsy_is_active(['valid_until' => '2026-10-31'], $t('2026-11-01 00:00'), $cr), false);
check('before from', rsy_is_active(['valid_from' => '2026-10-10'], $t('2026-10-09 12:00'), $cr), false);
check('bad timezone falls back, no crash', is_bool(rsy_is_active(['days' => [0]], $t('2026-09-28 12:00'), 'Nope/Zone')), true);
check('bad window is inactive, not always-on', rsy_is_active(['window' => ['from' => 'x', 'to' => '10:00']], $t('2026-09-28 12:00'), $cr), false);
check('zero-length window is inactive', rsy_is_active(['window' => ['from' => '10:00', 'to' => '10:00']], $t('2026-09-28 10:00'), $cr), false);
check('label', rsy_label(['days' => [0]]), 'Disponible los lunes');
check('label two days and window', rsy_label(['days' => [5, 6], 'window' => ['from' => '17:00', 'to' => '22:00']]), 'Disponible los sábados y domingos de 17:00 a 22:00');
check('label empty', rsy_label([]), '');

echo $fail ? "$fail failed\n" : "all passed\n";
exit($fail ? 1 : 0);
