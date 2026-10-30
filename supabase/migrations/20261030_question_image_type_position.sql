-- Add is_question_image and show_right to question_image_relations
-- is_question_image: false = explanation image (default, backward compat)
--                   true  = question image (new)
-- show_right:        false = below question text (default)
--                   true  = right of question text

ALTER TABLE question_image_relations
  ADD COLUMN IF NOT EXISTS is_question_image boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS show_right boolean NOT NULL DEFAULT false;
