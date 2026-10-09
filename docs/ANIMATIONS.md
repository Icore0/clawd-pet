# Animations

56 clips, generated from the app's catalog (`Wigglet --dump-catalog`). Do not edit by hand: run `python3 docs/assets/build/render.py`.

Status `needs-verify` means the trigger is implemented but no recorded hook payload in `fixtures/` exercises it yet.

| id | trigger | how detected | priority | duration | loop | props | sound | status | tracks |
|---|---|---|---|---|---|---|---|---|---|
| read | read | mood working, kind read | 30 | 4.5 | yes | book |  | done | anticipation 0.2, action 4.0, settle 0.3 |
| edit | edit | mood working, kind edit | 30 | 2.5 | yes | laptop |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| search | search | mood working, kind search | 30 | 3.5 | yes | glass |  | done | anticipation 0.2, action 3.0, settle 0.3 |
| web | web | mood working, kind web | 30 | 2.5 | yes | page |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| agent | agent | mood working, kind agent | 30 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| plan | plan | mood working, kind plan | 30 | 3.5 | yes |  |  | done | anticipation 0.2, action 3.0, settle 0.3 |
| test | test | mood working, kind test | 30 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| build | build | mood working, kind build | 30 | 3.4 | yes |  |  | done | anticipation 0.4, action 2.5, settle 0.5 |
| git | git | mood working, kind git | 30 | 3.5 | yes |  |  | done | anticipation 0.2, action 3.0, settle 0.3 |
| install | install | mood working, kind install | 30 | 3.83 | yes |  |  | done | anticipation 0.2, action 3.33, settle 0.3 |
| ask | waiting | mood waiting, kind is not yourTurn | 60 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| done | done | mood done | 40 | 2.5 | no |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| oops | oops | mood oops | 50 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| hello | hello | mood hello | 40 | 2.5 | no |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| bye | bye | mood bye | 40 | 2.5 | no |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| think | working | mood working, kind has no activity entry | 30 | 3.5 | yes |  |  | done | anticipation 0.2, action 3.0, settle 0.3 |
| breathe | ambient | weighted idle pool | 10 | 4.5 | yes |  |  | done | anticipation 0.2, action 4.0, settle 0.3 |
| glance | ambient | weighted idle pool | 10 | 4.67 | yes |  |  | done | anticipation 0.2, action 4.17, settle 0.3 |
| stretch | ambient | weighted idle pool, or a 2h session for 3s every 10min | 10 | 3.0 | yes |  |  | done | anticipation 0.2, action 2.5, settle 0.3 |
| yawn | ambient | weighted idle pool | 10 | 3.5 | yes |  |  | done | anticipation 0.2, action 3.0, settle 0.3 |
| dance | ambient | weighted idle pool | 10 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| hum | ambient | weighted idle pool | 10 | 4.5 | yes |  |  | done | anticipation 0.2, action 4.0, settle 0.3 |
| juggle | ambient | weighted idle pool | 10 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| dream | ambient | weighted idle pool | 10 | 4.5 | yes |  |  | done | anticipation 0.2, action 4.0, settle 0.3 |
| sleep | sleep | sleeping flag, or idle 120s | 20 | 4.5 | yes |  |  | done | anticipation 0.2, action 4.0, settle 0.3 |
| drag | drag | isDragging | 40 | 1.0 | yes |  |  | done | anticipation 0.2, action 0.5, settle 0.3 |
| pet | pet | petUntil still ahead | 40 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| listen | listen | listening | 40 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| chatThink | chatThink | chatBusy | 40 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| chatTalk | chatTalk | chat reply younger than 3s | 40 | 1.83 | yes |  |  | done | anticipation 0.2, action 1.33, settle 0.3 |
| testPass | testPass | a test command finished, first 2.5s | 40 | 3.0 | no | check |  | done | anticipation 0.2, action 2.5, settle 0.3 |
| testFail | testFail | a test command failed, first 2.5s | 50 | 2.5 | no | x |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| handoff | handoff | a sub-agent started, first 2.5s | 40 | 3.0 | no | parcel |  | done | anticipation 0.2, action 2.5, settle 0.3 |
| grind | grind | working turn longer than 20 min, 3s every 5 min | 40 | 3.5 | no |  |  | done | anticipation 0.2, action 3.0, settle 0.3 |
| deploy | deploy | command vercel, netlify, fly deploy, npm publish, or docker push | 30 | 5.0 | yes | mark |  | done | anticipation 0.45, action 4.0, settle 0.55 |
| push | push | command git push | 30 | 3.5 | yes | plane |  | done | anticipation 0.2, action 3.0, settle 0.3 |
| pull | pull | command git pull or git fetch | 30 | 3.83 | yes | parcel |  | done | anticipation 0.2, action 3.33, settle 0.3 |
| webSearch | webSearch | WebSearch | 30 | 2.5 | yes | glass |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| sweat | sweat | tool running longer than 60s | 40 | 2.5 | yes | drop |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| tea | tea | tool running longer than 180s | 40 | 4.5 | yes | cup |  | done | anticipation 0.2, action 4.0, settle 0.3 |
| frantic | frantic | 15 tool starts inside 10s | 40 | 1.13 | yes | lines |  | done | anticipation 0.05, action 1.0, settle 0.08 |
| watch | watch | waiting longer than 120s | 60 | 3.5 | yes | circle |  | done | anticipation 0.2, action 3.0, settle 0.3 |
| flag | flag | waiting longer than 600s | 60 | 2.5 | yes | flag |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| confetti | confetti | tool 100 or first commit today, 2s | 40 | 2.5 | no | dots |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| nightcap | nightcap | idle, local hour 1 through 4 | 20 | 4.5 | yes | moon |  | done | anticipation 0.2, action 4.0, settle 0.3 |
| conflict | conflict | failure text has CONFLICT or Automatic merge failed | 50 | 2.5 | no | mark |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| highFive | team | two done moods within 3s | 40 | 1.9 | no |  |  | done | anticipation 0.15, action 1.5, settle 0.25 |
| wave | team | a session sid newly appeared | 40 | 1.84 | no |  |  | done | anticipation 0.12, action 1.5, settle 0.22 |
| parcel | team | done while another session works, then sleep | 40 | 2.75 | no | parcel |  | done | anticipation 0.35, action 2.0, settle 0.4 |
| nap | team | every session idle for 120s | 20 | 4.1 | yes |  |  | done | anticipation 0.5, action 3.0, settle 0.6 |
| hop | team | every session mood is done | 40 | 1.28 | yes |  |  | done | anticipation 0.1, action 1.0, settle 0.18 |
| dizzy | dizzy | hold and shake | 40 | 2.75 | no |  |  | done | anticipation 0.09, action 2.5, settle 0.16 |
| offline | chat | chat status offline | 40 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| outOfCredits | chat | chat status outOfCredits | 40 | 3.0 | yes |  |  | done | anticipation 0.2, action 2.5, settle 0.3 |
| rateLimited | chat | chat status rateLimited | 40 | 2.5 | yes |  |  | done | anticipation 0.2, action 2.0, settle 0.3 |
| timeout | chat | chat status timeout | 40 | 3.5 | yes |  |  | done | anticipation 0.2, action 3.0, settle 0.3 |
