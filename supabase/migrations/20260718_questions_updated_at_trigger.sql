create or replace function public.set_questions_updated_at()
returns trigger
language plpgsql
as $function$
begin
    if (old.question is distinct from new.question or
        old.answer_1 is distinct from new.answer_1 or
        old.answer_2 is distinct from new.answer_2 or
        old.answer_3 is distinct from new.answer_3 or
        old.answer_4 is distinct from new.answer_4 or
        old.answer_5 is distinct from new.answer_5 or
        old.answer_6 is distinct from new.answer_6 or
        old.answer_7 is distinct from new.answer_7 or
        old.answer_8 is distinct from new.answer_8 or
        old.answer_9 is distinct from new.answer_9 or
        old.answer_10 is distinct from new.answer_10 or
        old.answer_11 is distinct from new.answer_11 or
        old.correct_answer is distinct from new.correct_answer or
        old.explanation is distinct from new.explanation or
        old.subject is distinct from new.subject or
        old.title is distinct from new.title or
        old.sub_title is distinct from new.sub_title or
        old.ref is distinct from new.ref or
        old.audio_url is distinct from new.audio_url or
        old.audio_duration_seconds is distinct from new.audio_duration_seconds or
        old.audio_highlights is distinct from new.audio_highlights) then
        new.updated_at = now();
    else
        new.updated_at = old.updated_at;
    end if;
    return new;
end;
$function$;