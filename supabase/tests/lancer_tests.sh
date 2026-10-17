#!/usr/bin/env bash
# Teste les migrations Supabase dans un PostgreSQL 17 LOCAL et jetable
# (conteneur Docker) — jamais sur la base distante.
#
#   bash supabase/tests/lancer_tests.sh
#
# Étapes : simulation de Supabase → schéma actuel (sans Storage) → données
# existantes → migration (deux fois : ré-exécutable) → tests.
set -euo pipefail
cd "$(dirname "$0")/.."
CONTENEUR=jarvis-pg-test-$$
docker run -d --rm --name "$CONTENEUR" -e POSTGRES_PASSWORD=local_jetable postgres:17 >/dev/null
trap 'docker stop "$CONTENEUR" >/dev/null' EXIT
until docker exec "$CONTENEUR" pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done
sleep 2

psql() { docker exec -i "$CONTENEUR" psql -U postgres -v ON_ERROR_STOP=1 -q -t "$@"; }

psql < tests/00_simulation_supabase.sql
# Schéma de référence sans la partie Storage (propre à Supabase).
sed '/^-- Storage : bucket/,/^-- Vues de consultation/d' schema.sql | psql
psql < tests/05_donnees_existantes.sql
for m in migrations/*.sql; do psql < "$m"; psql < "$m"; done
cat tests/[1-9]*_test.sql | psql 2>&1 | sed 's/^psql:<stdin>:[0-9]*: //'

# Doubles appels simultanés : la session 1 garde sa transaction ouverte 3 s,
# la session 2 envoie la même pièce jointe pendant ce temps.
APPEL="select public.enregistrer_contexte_whatsapp('dddddddd-0000-0000-0000-000000000001',
  'dddddddd-0000-0000-0000-00000000cccc', 'dddddddd-0000-0000-0000-00000000aaaa', null,
  'Simultané.', '{\"contact_name\":\"Rhodey\"}',
  '[{\"message_order\":0},{\"message_order\":1}]');"
docker exec -i "$CONTENEUR" psql -U postgres -q -t >/dev/null 2>&1 <<SQL &
begin; set local role service_role; $APPEL select pg_sleep(3); commit;
SQL
sleep 1
SECONDE=$(docker exec -i "$CONTENEUR" psql -U postgres -q -t 2>&1 <<SQL
set role service_role; $APPEL
SQL
)
wait
echo "$SECONDE" | grep -q "23505\|duplicate key" && echo "OK P2. appel simultané : le second échoue (23505), le backend relit le premier"
RESTE=$(docker exec -i "$CONTENEUR" psql -U postgres -q -t -A <<SQL
select (select count(*) from public.conversation_contexts where id = 'dddddddd-0000-0000-0000-00000000cccc')
  || '/' || (select count(*) from public.context_messages where context_id = 'dddddddd-0000-0000-0000-00000000cccc')
  || '/' || (select count(*) from public.conversations where title = 'Rhodey');
SQL
)
[ "$RESTE" = "1/2/1" ] && echo "OK P2. appels simultanés : un seul contexte complet, une seule conversation" || echo "ÉCHEC simultané : $RESTE"

# Phase 5 : deux ajouts simultanés au même contexte (verrou du contexte) :
# rangs distincts, aucun perdu.
AJOUT() { echo "select public.ajouter_messages_contexte('dddddddd-0000-0000-0000-000000000001',
  'dddddddd-0000-0000-0000-00000000c0a1', '[{\"id\":\"$1\",\"origin\":\"manual_received\",\"author\":\"Tony Stark\",\"content\":\"$2\"}]');"; }
docker exec -i "$CONTENEUR" psql -U postgres -q -t >/dev/null 2>&1 <<SQL &
begin; set local role service_role; $(AJOUT 22222222-5555-0000-0000-000000000001 premier) select pg_sleep(3); commit;
SQL
sleep 1
docker exec -i "$CONTENEUR" psql -U postgres -q -t >/dev/null 2>&1 <<SQL
set role service_role; $(AJOUT 22222222-5555-0000-0000-000000000002 second)
SQL
wait
RANGS=$(docker exec -i "$CONTENEUR" psql -U postgres -q -t -A <<SQL
select string_agg(content || '=' || message_order, ',' order by message_order) from public.context_messages
 where id in ('22222222-5555-0000-0000-000000000001', '22222222-5555-0000-0000-000000000002');
SQL
)
[ "$RANGS" = "premier=6,second=7" ] && echo "OK P5. ajouts simultanés : sérialisés, rangs distincts" || echo "ÉCHEC ajouts simultanés : $RANGS"

# Phase 5.1 : deux appareils déclarent deux propositions différentes du même
# ensemble au même instant : un seul choix actif.
DECL() { echo "select public.declarer_reponse_envoyee('dddddddd-0000-0000-0000-000000000001',
  'dddddddd-0000-0000-0000-0000000000c1', 'dddddddd-0000-0000-0000-0000000005e1',
  '{\"type\":\"reponse_envoyee\",\"statut\":\"declaree_envoyee\",\"proposition_id\":\"$1\"}');"; }
docker exec -i "$CONTENEUR" psql -U postgres -q -t >/dev/null 2>&1 <<SQL
set role service_role; select public.annuler_reponse_envoyee('dddddddd-0000-0000-0000-000000000001',
  'dddddddd-0000-0000-0000-0000000000c1', 'dddddddd-0000-0000-0000-0000000005e1', 'p2', now());
SQL
docker exec -i "$CONTENEUR" psql -U postgres -q -t >/dev/null 2>&1 <<SQL &
begin; set local role service_role; $(DECL pa) select pg_sleep(3); commit;
SQL
sleep 1
SECOND=$(docker exec -i "$CONTENEUR" psql -U postgres -q -t -A <<SQL
set role service_role; $(DECL pb)
SQL
)
wait
ACTIFS=$(docker exec -i "$CONTENEUR" psql -U postgres -q -t -A <<SQL
select string_agg(e ->> 'proposition_id', ',') from public.messages m, jsonb_array_elements(m.attachments) e
 where m.id = 'dddddddd-0000-0000-0000-0000000005e1' and e ->> 'statut' = 'declaree_envoyee';
SQL
)
echo "$SECOND" | grep -q deja_choisi && [ "$ACTIFS" = "pa" ] && echo "OK P5.1 choix simultanés : un seul actif" || echo "ÉCHEC choix simultanés : $SECOND / $ACTIFS"
