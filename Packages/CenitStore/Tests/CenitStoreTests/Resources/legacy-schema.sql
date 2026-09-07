CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
CREATE TABLE IF NOT EXISTS "cursors" ("name" TEXT PRIMARY KEY, "value" INTEGER);
CREATE TABLE IF NOT EXISTS "sleepSession" ("deviceId" TEXT NOT NULL, "startTs" INTEGER NOT NULL, "endTs" INTEGER NOT NULL, "efficiency" DOUBLE, "restingHr" INTEGER, "avgHrv" DOUBLE, "stagesJSON" TEXT, PRIMARY KEY ("deviceId", "startTs"));
CREATE TABLE IF NOT EXISTS "dailyMetric" ("deviceId" TEXT NOT NULL, "day" TEXT NOT NULL, "totalSleepMin" DOUBLE, "efficiency" DOUBLE, "deepMin" DOUBLE, "remMin" DOUBLE, "lightMin" DOUBLE, "disturbances" INTEGER, "restingHr" INTEGER, "avgHrv" DOUBLE, "recovery" DOUBLE, "strain" DOUBLE, "exerciseCount" INTEGER, "spo2Pct" DOUBLE, "skinTempDevC" DOUBLE, "respRateBpm" DOUBLE, "steps" INTEGER, "activeKcalEst" DOUBLE, "effortConfidence" TEXT, "restConfidence" TEXT, PRIMARY KEY ("deviceId", "day"));
CREATE TABLE IF NOT EXISTS "journal" ("deviceId" TEXT NOT NULL, "day" TEXT NOT NULL, "question" TEXT NOT NULL, "answeredYes" INTEGER NOT NULL, "notes" TEXT, PRIMARY KEY ("deviceId", "day", "question"));
CREATE TABLE IF NOT EXISTS "workout" ("deviceId" TEXT NOT NULL, "startTs" INTEGER NOT NULL, "endTs" INTEGER NOT NULL, "sport" TEXT NOT NULL, "source" TEXT NOT NULL, "durationS" DOUBLE, "energyKcal" DOUBLE, "avgHr" INTEGER, "maxHr" INTEGER, "strain" DOUBLE, "distanceM" DOUBLE, "zonesJSON" TEXT, "notes" TEXT, PRIMARY KEY ("deviceId", "startTs", "sport"));
CREATE TABLE IF NOT EXISTS "appleDaily" ("deviceId" TEXT NOT NULL, "day" TEXT NOT NULL, "steps" INTEGER, "activeKcal" DOUBLE, "basalKcal" DOUBLE, "vo2max" DOUBLE, "avgHr" INTEGER, "maxHr" INTEGER, "walkingHr" INTEGER, "weightKg" DOUBLE, PRIMARY KEY ("deviceId", "day"));
CREATE TABLE IF NOT EXISTS "metricSeries" ("deviceId" TEXT NOT NULL, "day" TEXT NOT NULL, "key" TEXT NOT NULL, "value" DOUBLE NOT NULL, PRIMARY KEY ("deviceId", "day", "key"));
CREATE INDEX "idx_metricSeries_device_key_day" ON "metricSeries"("deviceId", "key", "day");
CREATE TABLE IF NOT EXISTS "experiment" ("id" TEXT PRIMARY KEY, "deviceId" TEXT NOT NULL, "behavior" TEXT NOT NULL, "outcome" TEXT NOT NULL, "expectedSign" INTEGER NOT NULL, "startDay" TEXT NOT NULL, "windowDays" INTEGER NOT NULL, "status" TEXT NOT NULL, "result" TEXT, "effectDelta" DOUBLE, "effectSize" DOUBLE, "pValue" DOUBLE, "nWith" INTEGER, "nWithout" INTEGER, "createdAt" INTEGER NOT NULL, "decidedAt" INTEGER);
CREATE TABLE IF NOT EXISTS "customExercise" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL, "type" TEXT NOT NULL, "equipment" TEXT, "primaryMuscles" TEXT NOT NULL, "secondaryMuscles" TEXT NOT NULL, "cues" TEXT NOT NULL, "bodyParts" TEXT NOT NULL DEFAULT '[]', "gifUrl" TEXT);
CREATE TABLE IF NOT EXISTS "routine" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL, "tag" TEXT, "createdTs" INTEGER NOT NULL, "updatedTs" INTEGER NOT NULL, "sortOrder" INTEGER NOT NULL DEFAULT 0, "folderId" TEXT);
CREATE TABLE IF NOT EXISTS "routineExercise" ("id" TEXT PRIMARY KEY, "routineId" TEXT NOT NULL, "exerciseId" TEXT NOT NULL, "position" INTEGER NOT NULL, "targetSets" INTEGER NOT NULL, "targetReps" INTEGER, "targetWeightKg" DOUBLE, "warmupPercents" TEXT NOT NULL, "restMode" TEXT NOT NULL, "restSeconds" INTEGER NOT NULL, "supersetGroup" INTEGER, "hrRestReference" TEXT NOT NULL DEFAULT 'restingMargin', "hrRestValue" DOUBLE NOT NULL DEFAULT 0, "progressionEnabled" INTEGER NOT NULL DEFAULT 0, "progressionSessions" INTEGER NOT NULL DEFAULT 2, "progressionIncrementKg" DOUBLE, "progressionDeload" TEXT NOT NULL DEFAULT 'propose', "progressionIgnoreRecovery" INTEGER NOT NULL DEFAULT 0, "note" TEXT, "progressionUseRPE" INTEGER NOT NULL DEFAULT 0);
CREATE INDEX "idx_routineExercise_routine_pos" ON "routineExercise"("routineId", "position");
CREATE TABLE IF NOT EXISTS "strengthSession" ("id" TEXT PRIMARY KEY, "routineId" TEXT, "startTs" INTEGER NOT NULL, "endTs" INTEGER, "deviceId" TEXT, "strain" DOUBLE, "avgHr" INTEGER, "notes" TEXT, "energyKcal" DOUBLE, "energySource" TEXT, "strainSource" TEXT, "sessionRpe" DOUBLE, "sessionRpeSource" TEXT, "trimpPerAU" DOUBLE, "source" TEXT, "title" TEXT, "programWeek" INTEGER, "deload" INTEGER);
CREATE TABLE IF NOT EXISTS "setEntry" ("id" TEXT PRIMARY KEY, "sessionId" TEXT NOT NULL, "exerciseId" TEXT NOT NULL, "position" INTEGER NOT NULL, "kind" TEXT NOT NULL, "weightKg" DOUBLE, "reps" INTEGER, "timeS" DOUBLE, "distanceM" DOUBLE, "done" BOOLEAN NOT NULL DEFAULT 0, "ts" INTEGER NOT NULL, "rpe" DOUBLE, "restTakenS" INTEGER, "mode" TEXT);
CREATE INDEX "idx_setEntry_session_pos" ON "setEntry"("sessionId", "position");
CREATE INDEX "idx_setEntry_exercise_ts" ON "setEntry"("exerciseId", "ts");
CREATE TABLE IF NOT EXISTS "personalRecord" ("id" TEXT PRIMARY KEY, "exerciseId" TEXT NOT NULL, "metric" TEXT NOT NULL, "valueKg" DOUBLE, "reps" INTEGER, "ts" INTEGER NOT NULL);
CREATE INDEX "idx_personalRecord_exercise" ON "personalRecord"("exerciseId");
CREATE TABLE IF NOT EXISTS "dietPlan" ("id" TEXT PRIMARY KEY, "deviceId" TEXT NOT NULL, "nombre" TEXT NOT NULL, "idioma" TEXT NOT NULL, "ciclo" TEXT NOT NULL, "payloadJSON" TEXT NOT NULL, "createdAt" INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS "dietAdherence" ("deviceId" TEXT NOT NULL, "day" TEXT NOT NULL, "mealId" TEXT NOT NULL, "status" TEXT NOT NULL, "note" TEXT, "optionIndex" INTEGER, PRIMARY KEY ("deviceId", "day", "mealId"));
CREATE TABLE IF NOT EXISTS "routineSet" ("id" TEXT PRIMARY KEY, "routineExerciseId" TEXT NOT NULL, "position" INTEGER NOT NULL, "kind" TEXT NOT NULL, "reps" INTEGER, "weightKg" DOUBLE, "restMode" TEXT, "restSeconds" INTEGER, "hrRestReference" TEXT, "hrRestValue" DOUBLE, "repsRangeTop" INTEGER, "mode" TEXT);
CREATE INDEX "idx_routineSet_re_pos" ON "routineSet"("routineExerciseId", "position");
CREATE TABLE IF NOT EXISTS "routineFolder" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL, "sortOrder" INTEGER NOT NULL DEFAULT 0);
CREATE TABLE deviceIdMap (
    deviceId TEXT PRIMARY KEY NOT NULL,
    intId INTEGER NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS "hrSample" (
    deviceId INTEGER NOT NULL, ts INTEGER NOT NULL, bpm INTEGER NOT NULL,
    PRIMARY KEY (deviceId, ts)
) STRICT, WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS "rrInterval" (
    deviceId INTEGER NOT NULL, ts INTEGER NOT NULL, rrMs INTEGER NOT NULL,
    PRIMARY KEY (deviceId, ts, rrMs)
) STRICT, WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS "learnedExerciseAlias" ("name" TEXT PRIMARY KEY, "exerciseId" TEXT NOT NULL, "ts" INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS "routineSchedule" ("weekday" INTEGER PRIMARY KEY, "routineId" TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS "exerciseTypeOverride" ("exerciseId" TEXT PRIMARY KEY, "type" TEXT NOT NULL, "ts" INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS "inProgressStrengthSession" ("id" TEXT PRIMARY KEY, "snapshot" TEXT NOT NULL, "updatedTs" INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS "progressionOptOut" ("sessionId" TEXT NOT NULL, "exerciseId" TEXT NOT NULL, PRIMARY KEY ("sessionId", "exerciseId"));
CREATE TABLE strengthExerciseNote (
    id TEXT PRIMARY KEY, sessionId TEXT NOT NULL, exerciseId TEXT NOT NULL,
    setPosition INTEGER, text TEXT NOT NULL, ts INTEGER NOT NULL);
CREATE INDEX idx_exNote_ex ON strengthExerciseNote(exerciseId, ts);
CREATE INDEX idx_exNote_sess ON strengthExerciseNote(sessionId);
CREATE TABLE IF NOT EXISTS "strengthHrSample" ("sessionId" TEXT NOT NULL, "ts" INTEGER NOT NULL, "bpm" INTEGER NOT NULL, PRIMARY KEY ("sessionId", "ts"));
CREATE TABLE IF NOT EXISTS "program" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL, "weeks" INTEGER NOT NULL, "startTs" INTEGER NOT NULL, "deloadRule" TEXT NOT NULL, "endMode" TEXT NOT NULL, "templateId" TEXT, "createdTs" INTEGER NOT NULL);
