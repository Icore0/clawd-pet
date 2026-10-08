# Animations

86 clips, generated from the app's catalog (`Wigglet --dump-catalog`). Do not edit by hand: run `python3 docs/assets/build/render.py`.

Status `needs-verify` means the trigger is implemented but no recorded hook payload in `fixtures/` exercises it yet.

| id | trigger | how detected | priority | duration | loop | props | sound | status | tracks |
|---|---|---|---|---|---|---|---|---|---|
| read | read | mood working, kind read | 30 | 2.5 | yes | book |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| edit | edit | mood working, kind edit | 30 | 2.5 | yes | laptop |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| bash | bash | mood working, kind bash | 30 | 2.42 | yes | laptop |  | done | anticipation 0.2, action 1.92, settle 0.3 |
| search | search | mood working, kind search | 30 | 2.5 | yes | glass |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| web | web | mood working, kind web | 30 | 1.83 | yes | page |  | done | anticipation 0.2, action 1.33, settle 0.3 |
| agent | agent | mood working, kind agent | 30 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| plan | plan | mood working, kind plan | 30 | 2.0 | yes |  |  | done | anticipation 0.2, action 1.5, settle 0.3 |
| compact | compact | mood working, kind compact | 30 | 1.58 | yes |  |  | done | anticipation 0.2, action 1.08, settle 0.3 |
| test | test | mood working, kind test | 30 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| build | build | mood working, kind build | 30 | 1.9 | yes |  |  | done | anticipation 0.4, action 1.0, settle 0.5 |
| git | git | mood working, kind git | 30 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| install | install | mood working, kind install | 30 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| ask | waiting | mood waiting, kind is not yourTurn | 60 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| yourTurn | waiting | mood waiting, kind yourTurn | 60 | 2.67 | yes |  |  | done | anticipation 0.2, action 2.17, settle 0.3 |
| done | done | mood done | 40 | 2.42 | no |  |  | done | anticipation 0.2, action 1.92, settle 0.3 |
| oops | oops | mood oops | 50 | 2.0 | yes |  |  | done | anticipation 0.2, action 1.5, settle 0.3 |
| hello | hello | mood hello | 40 | 3.25 | no |  |  | done | anticipation 0.2, action 2.75, settle 0.3 |
| bye | bye | mood bye | 40 | 3.33 | no |  |  | done | anticipation 0.2, action 2.83, settle 0.3 |
| think | working | mood working, kind has no activity entry | 30 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| breathe | ambient | weighted idle pool | 10 | 3.83 | yes |  |  | done | anticipation 0.2, action 3.33, settle 0.3 |
| blink | ambient | weighted idle pool | 10 | 2.30 | yes |  |  | done | anticipation 0.05, action 2.17, settle 0.08 |
| glance | ambient | weighted idle pool | 10 | 3.83 | yes |  |  | done | anticipation 0.2, action 3.33, settle 0.3 |
| stretch | ambient | weighted idle pool, or a 2h session for 3s every 10min | 10 | 2.58 | yes |  |  | done | anticipation 0.2, action 2.08, settle 0.3 |
| yawn | ambient | weighted idle pool | 10 | 3.0 | yes |  |  | done | anticipation 0.2, action 2.5, settle 0.3 |
| dance | ambient | weighted idle pool | 10 | 1.33 | yes |  |  | done | anticipation 0.2, action 0.83, settle 0.3 |
| hum | ambient | weighted idle pool | 10 | 1.83 | yes |  |  | done | anticipation 0.2, action 1.33, settle 0.3 |
| mote | ambient | weighted idle pool | 10 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| juggle | ambient | weighted idle pool | 10 | 1.0 | yes |  |  | done | anticipation 0.2, action 0.5, settle 0.3 |
| dream | ambient | weighted idle pool | 10 | 2.17 | yes |  |  | done | anticipation 0.2, action 1.67, settle 0.3 |
| sleep | sleep | sleeping flag, or idle 120s | 20 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| drag | drag | isDragging | 40 | 1.0 | yes |  |  | done | anticipation 0.2, action 0.5, settle 0.3 |
| glide | glide | isGliding | 40 | 1.6 | yes |  |  | done | anticipation 0.2, action 1.1, settle 0.3 |
| pet | pet | petUntil still ahead | 40 | 1.67 | yes |  |  | done | anticipation 0.2, action 1.17, settle 0.3 |
| listen | listen | listening | 40 | 1.5 | yes |  |  | done | anticipation 0.2, action 1.0, settle 0.3 |
| chatThink | chatThink | chatBusy | 40 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| chatTalk | chatTalk | chat reply younger than 3s | 40 | 1.5 | yes |  |  | done | anticipation 0.2, action 1.0, settle 0.3 |
| testPass | testPass | a test command finished, first 2.5s | 40 | 2.67 | no | check |  | done | anticipation 0.2, action 2.17, settle 0.3 |
| testFail | testFail | a test command failed, first 2.5s | 50 | 2.5 | no | x |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| handoff | handoff | a sub-agent started, first 2.5s | 40 | 1.92 | no | parcel |  | done | anticipation 0.2, action 1.42, settle 0.3 |
| grind | grind | working turn longer than 20 min, 3s every 5 min | 40 | 3.58 | no |  |  | done | anticipation 0.2, action 3.08, settle 0.3 |
| deploy | deploy | command vercel, netlify, fly deploy, npm publish, or docker push | 30 | 3.0 | yes | mark |  | done | anticipation 0.45, action 2.0, settle 0.55 |
| commit | commit | command git commit | 30 | 2.08 | yes | seal |  | done | anticipation 0.2, action 1.58, settle 0.3 |
| push | push | command git push | 30 | 2.42 | yes | plane |  | done | anticipation 0.2, action 1.92, settle 0.3 |
| pull | pull | command git pull or git fetch | 30 | 2.5 | yes | parcel |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| lint | lint | command eslint, prettier, or ruff | 30 | 1.5 | yes | brush |  | done | anticipation 0.2, action 1.0, settle 0.3 |
| migrate | migrate | command prisma, alembic, or psql | 30 | 1.0 | yes | boxes |  | done | anticipation 0.2, action 0.5, settle 0.3 |
| docker | docker | command docker or compose | 30 | 1.83 | yes | box |  | done | anticipation 0.2, action 1.33, settle 0.3 |
| serve | serve | command npm run dev or uvicorn | 30 | 2.08 | yes | lantern |  | done | anticipation 0.2, action 1.58, settle 0.3 |
| mcp | mcp | tool name starts with mcp__ | 30 | 1.5 | yes | line |  | done | anticipation 0.2, action 1.0, settle 0.3 |
| burstRead | burstRead | 3 Reads inside 5s | 30 | 1.0 | yes | pages |  | done | anticipation 0.2, action 0.5, settle 0.3 |
| notebook | notebook | NotebookEdit | 30 | 2.0 | yes | page |  | done | anticipation 0.2, action 1.5, settle 0.3 |
| webSearch | webSearch | WebSearch | 30 | 1.83 | yes | glass |  | done | anticipation 0.2, action 1.33, settle 0.3 |
| webFetch | webFetch | WebFetch | 30 | 2.08 | yes | page |  | done | anticipation 0.2, action 1.58, settle 0.3 |
| bandage | bandage | errorStreak 3 or more | 50 | 2.42 | yes | mark |  | done | anticipation 0.2, action 1.92, settle 0.3 |
| sweat | sweat | tool running longer than 60s | 40 | 1.92 | yes | drop |  | done | anticipation 0.2, action 1.42, settle 0.3 |
| tea | tea | tool running longer than 180s | 40 | 2.5 | yes | cup |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| book | book | tool running longer than 600s | 40 | 2.58 | yes | rectangle |  | done | anticipation 0.2, action 2.08, settle 0.3 |
| frantic | frantic | 15 tool starts inside 10s | 40 | 0.30 | yes | lines |  | done | anticipation 0.05, action 0.17, settle 0.08 |
| watch | watch | waiting longer than 120s | 60 | 2.33 | yes | circle |  | done | anticipation 0.2, action 1.83, settle 0.3 |
| flag | flag | waiting longer than 600s | 60 | 1.17 | yes | flag |  | done | anticipation 0.2, action 0.67, settle 0.3 |
| coffee | coffee | earliest session today, first 30s | 20 | 2.5 | yes | cup |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| confetti | confetti | tool 100 or first commit today, 2s | 40 | 2.25 | no | dots |  | done | anticipation 0.2, action 1.75, settle 0.3 |
| nightcap | nightcap | idle, local hour 1 through 4 | 20 | 2.5 | yes | moon |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| conflict | conflict | failure text has CONFLICT or Automatic merge failed | 50 | 2.08 | no | mark |  | done | anticipation 0.2, action 1.58, settle 0.3 |
| conflictStare | team | two edits of the same file within 60s | 40 | 2.27 | yes |  |  | done | anticipation 0.25, action 1.67, settle 0.35 |
| highFive | team | two done moods within 3s | 40 | 2.07 | no |  |  | done | anticipation 0.15, action 1.67, settle 0.25 |
| wave | team | a session sid newly appeared | 40 | 2.34 | no |  |  | done | anticipation 0.12, action 2.0, settle 0.22 |
| parcel | team | done while another session works, then sleep | 40 | 2.25 | no | parcel |  | done | anticipation 0.35, action 1.5, settle 0.4 |
| nap | team | every session idle for 120s | 20 | 3.1 | yes |  |  | done | anticipation 0.5, action 2.0, settle 0.6 |
| bump | team | grabbed slot overlaps a sibling | 40 | 0.62 | no |  |  | done | anticipation 0.08, action 0.42, settle 0.12 |
| hop | team | every session mood is done | 40 | 1.36 | yes |  |  | done | anticipation 0.1, action 1.08, settle 0.18 |
| poke | poke | single click without a drag | 40 | 0.74 | no |  |  | done | anticipation 0.06, action 0.58, settle 0.1 |
| spin | spin | second click within 0.35s | 40 | 0.96 | no |  |  | done | anticipation 0.07, action 0.75, settle 0.14 |
| dizzy | dizzy | hold and shake | 40 | 1.25 | no |  |  | done | anticipation 0.09, action 1.0, settle 0.16 |
| lean | lean | hover one slot for 2s | 40 | 1.88 | yes |  |  | done | anticipation 0.18, action 1.42, settle 0.28 |
| peek | peek | panel origin within 8pt of a screen edge while dragging | 40 | 1.79 | yes |  |  | done | anticipation 0.22, action 1.25, settle 0.32 |
| opening | chat | chat status opening | 40 | 1.58 | yes |  |  | done | anticipation 0.2, action 1.08, settle 0.3 |
| listening | chat | chat status listening | 40 | 1.5 | yes |  |  | done | anticipation 0.2, action 1.0, settle 0.3 |
| reading | chat | chat status reading | 40 | 1.5 | yes |  |  | done | anticipation 0.2, action 1.0, settle 0.3 |
| thinking | chat | chat status thinking | 40 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| talking | chat | chat status talking | 40 | 1.5 | yes |  |  | done | anticipation 0.2, action 1.0, settle 0.3 |
| offline | chat | chat status offline | 40 | 2.17 | yes |  |  | done | anticipation 0.2, action 1.67, settle 0.3 |
| outOfCredits | chat | chat status outOfCredits | 40 | 2.17 | yes |  |  | done | anticipation 0.2, action 1.67, settle 0.3 |
| rateLimited | chat | chat status rateLimited | 40 | 2.17 | yes |  |  | done | anticipation 0.2, action 1.67, settle 0.3 |
| unauthorized | chat | chat status unauthorized | 40 | 2.17 | yes |  |  | done | anticipation 0.2, action 1.67, settle 0.3 |
| timeout | chat | chat status timeout | 40 | 2.17 | yes |  |  | done | anticipation 0.2, action 1.67, settle 0.3 |
