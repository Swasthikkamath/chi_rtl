-- Pandoc filter that applies the house conventions of the document series
-- this specification belongs to.
--
-- Three things are done here rather than in the Markdown source, so that the
-- source stays readable and the numbering cannot drift:
--
--   1. A level-one heading that starts with a number becomes a chapter
--      opening: the number is lifted onto its own line as "Chapter N", set
--      larger and unemphasised, and the title below it is centred and set in
--      capitals. The chapter number is taken from the heading text, so the
--      Markdown remains the single place where chapters are numbered.
--   2. Table captions are moved below the table. Pandoc's docx writer emits
--      them above, and this document series puts them underneath.
--   3. Both kinds of caption keep the paragraph styles the Word template
--      expects, which is what lets the List of Tables and List of Figures
--      fields find them.

local CHAPTER_RUN = table.concat({
  '<w:r><w:rPr><w:rStyle w:val="ChapterLabel"/></w:rPr>',
  '<w:t xml:space="preserve">Chapter %s</w:t></w:r>',
  '<w:r><w:br/><w:tab/></w:r>',
})

local function upper_case(inlines)
  return inlines:walk({
    -- Only literal text is raised. Inline code keeps its case because it names
    -- an identifier in the RTL.
    Str = function(el)
      return pandoc.Str(pandoc.text.upper(el.text))
    end,
  })
end

function Header(el)
  if el.level ~= 1 then
    return nil
  end

  local number = nil
  if #el.content > 0 and el.content[1].t == "Str" then
    number = el.content[1].text:match("^(%d+)$")
  end

  if number then
    -- Drop the number and the space that followed it.
    el.content:remove(1)
    while #el.content > 0 and el.content[1].t == "Space" do
      el.content:remove(1)
    end
  end

  el.content = upper_case(el.content)

  if number then
    el.content:insert(1, pandoc.RawInline("openxml", CHAPTER_RUN:format(number)))
  end
  return el
end

function Table(el)
  local caption = el.caption.long
  if #caption == 0 then
    return nil
  end
  el.caption.long = pandoc.Blocks({})
  local styled = pandoc.Div(caption, pandoc.Attr("", {}, {
    { "custom-style", "Table Caption" },
  }))
  return pandoc.Blocks({ el, styled })
end
