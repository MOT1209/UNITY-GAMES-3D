# Coaching staff system

`CoachingStaff` (`scripts/systems/development/coaching_staff.gd`) is the single source of coaching influence on training and development.

## Departments
attacking, midfield, defensive, goalkeeping, fitness, tactical (`DevConfig.DEPARTMENTS`). There is **no separate youth department**: youth coaching is modelled by assigning department coaches to an academy age group (`youth_group` U15 / U17 / U19). Status: implemented + tested.

## Which department trains what
`DevConfig.lead_department(attr)`: the seven broad attributes via `ATTRIBUTE_LEAD`; detailed attributes via `DETAIL_LEAD` (mental / tactical ones go to the tactical coach), otherwise the department of the broad parent. The tactical coach's share is added to the other departments' attributes (`TACTICAL_SHARE`) and is not applied twice to attributes he already leads. A coach specialisation favours its attributes (`SPECIALISATIONS` for broad, `SPEC_DETAILS` for detailed). Status: implemented + tested.

## Market, contracts, money (implemented + tested in `player_development_validation`)
Candidates with varied wage expectations; negotiation (refuse / counter / accept; a longer contract lowers the asking wage); hiring with signing bonus, wage-budget and balance checks; staff and per-department capacity from the training facility; weekly wages; contract expiry warning; renewal; dismissal with compensation; vacancies (a vacant department slows training but never blocks it); coach progression by experience and club success.

## Legacy staff (`StaffTeam`)
The old staff list keeps the assistant, doctor, chief scout and youth coach. `fitness_coach`, `goalkeeping_coach` and `first_team_coach` are bridged: a legacy member is imported once as the coach of the fitness / goalkeeping / tactical department (his wage is paid by `CoachingStaff` from then on, exactly one coach per department afterwards), and the old screen no longer lists those roles. Status: implemented + tested.

## No duplicate bonuses
* Academy development uses `DevelopmentEngine.best_academy_coaching`: the best of the development staff, the legacy youth coach and the academy's own coach - never their product.
* Youth league matches use `YouthDevelopment.match_coaching_factor`: the better of the academy coach and the specialist coach for the attribute and age group.
* First-team development uses `CoachingStaff.attribute_multiplier` only.

## Not implemented / limits
A dedicated youth-development department; coaches influencing loan growth or mentoring; coach effects on injuries other than the fitness department's share of training-caused risk.
