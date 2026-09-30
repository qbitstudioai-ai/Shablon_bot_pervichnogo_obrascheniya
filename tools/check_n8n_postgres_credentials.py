#!/usr/bin/env python3
import argparse, json, re
from collections import deque
from pathlib import Path

SERVICE_FUNCTIONS={
'zaregistrirovat_sluzhebnoe_sobytie','podtverdit_lichnyy_chat_menedzhera',
'zabrat_sozdanie_operator_temy','podtverdit_operator_temu','otmetit_temu_neizvestnoy',
'zabrat_sobytie_zerkala','zafiksirovat_rezultat_zerkala','zabrat_dialog_operatorom',
'vernut_dialog_botu','sozdat_ruchnoe_ishodyashchee','poluchit_sostoyanie_operatora'}
LEGACY_SERVICE_FUNCTIONS={'vzyat_sluzhebnoe_zadanie','vzyat_sleduyushchee_sluzhebnoe_zadanie',
'podgotovit_ruchnoy_otvet','podtverdit_ruchnoy_otvet','otmetit_neizvestnyy_ruchnoy_otvet',
'zaregistrirovat_menedzhera_telegram'}
GATES={
'Гейт_Обработка очереди':('processing','Взять следующее задание'),
'Гейт_Исходящая отправка':('outgoing','Взять исходящее действие'),
'Гейт_Напоминания':('reminders','Обработать следующее напоминание'),
'Гейт_Создание темы оператора':('operator_topic','Служебный_Взять создание темы оператора'),
'Гейт_Зеркало оператору':('operator_mirror','Служебный_Взять событие зеркала оператору')}
SEED_BOT='Сохранить вход и поставить в очередь'
SEED_SERVICE='Служебный_Сохранить служебный вход'

def cred(n):
 c=(n.get('credentials') or {}).get('postgres') or {}
 return (str(c.get('id') or ''),str(c.get('name') or ''))
def funcs(q):
 return set(re.findall(r'(?:(?:qbit_bot_pervichnogo_obrascheniya)\\.)?([a-z_][a-z0-9_]*)\\s*\\(',q or '',re.I))
def reachable(w):
 a={}
 for s,kinds in (w.get('connections') or {}).items():
  out=[]
  for branches in kinds.values():
   for arr in branches: out += [e.get('node') for e in arr if e.get('node')]
  a[s]=out
 starts=[n['name'] for n in w.get('nodes',[]) if n.get('type') in ('n8n-nodes-base.scheduleTrigger','n8n-nodes-base.webhook')]
 seen=set(starts); q=deque(starts)
 while q:
  s=q.popleft()
  for t in a.get(s,[]):
   if t not in seen: seen.add(t); q.append(t)
 return seen
def main():
 ap=argparse.ArgumentParser()
 ap.add_argument('workflow'); ap.add_argument('--template',action='store_true')
 a=ap.parse_args()
 try: w=json.loads(Path(a.workflow).read_text(encoding='utf-8'))
 except Exception as e: print('FAIL: invalid JSON:',e); return 2
 err=[]; nodes=w.get('nodes') or []; names=[n.get('name') for n in nodes]; by={n.get('name'):n for n in nodes}; ns=set(names)
 if len(names)!=len(ns): err.append('duplicate node names')
 if w.get('active') is not False: err.append('workflow active must be false')
 for s,kinds in (w.get('connections') or {}).items():
  if s not in ns: err.append('dangling source: '+s)
  for branches in kinds.values():
   for arr in branches:
    for e in arr:
     if e.get('node') not in ns: err.append('dangling target: '+str(e.get('node')))
 settings=(by.get('Настройки компании') or {}).get('parameters',{}).get('jsCode','')
 for key in [v[0] for v in GATES.values()]:
  if not re.search(r'\\b'+re.escape(key)+r'\\s*:\\s*false\\b',settings): err.append('gate default not false: '+key)
 for g,(key,target) in GATES.items():
  main=((w.get('connections') or {}).get(g) or {}).get('main') or []
  if len(main)<2: err.append('missing false output: '+g)
  else:
   if [x.get('node') for x in main[0]]!=[target]: err.append('wrong true route: '+g)
   if main[1]: err.append('false branch has downstream: '+g)
  if (by.get(target) or {}).get('disabled') is True: err.append('worker disabled/pass-through: '+target)
 reach=reachable(w)
 for n in names:
  if n and n.startswith('LEGACY_Служебный_') and n in reach: err.append('legacy reachable from trigger: '+n)
 pg=[n for n in nodes if n.get('type')=='n8n-nodes-base.postgres']
 if a.template:
  bad=[n['name'] for n in pg if (n.get('credentials') or {}).get('postgres')]
  if bad: err.append('template contains Postgres credentials')
 else:
  if SEED_BOT not in by or SEED_SERVICE not in by: err.append('missing seed nodes')
  else:
   bot,svc=cred(by[SEED_BOT]),cred(by[SEED_SERVICE])
   if not any(bot) or not any(svc): err.append('missing seed credential')
   elif bot==svc: err.append('bot/service credentials must differ')
   else:
    for n in pg:
     f=funcs(n.get('parameters',{}).get('query',''))
     service_sql=bool(f & (SERVICE_FUNCTIONS|LEGACY_SERVICE_FUNCTIONS))
     service_name=n['name'].startswith('Служебный_') or n['name'].startswith('LEGACY_Служебный_')
     if service_sql and not service_name: err.append('service SQL without service prefix: '+n['name'])
     if cred(n)!=(svc if service_name else bot): err.append('wrong Postgres credential class: '+n['name'])
 if err:
  for x in err: print('FAIL:',x)
  return 1
 print('OK: PostgreSQL credential routing and WF-02B3A safety gates verified.')
 return 0
if __name__=='__main__': raise SystemExit(main())
