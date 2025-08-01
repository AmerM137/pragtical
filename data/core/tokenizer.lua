local core = require "core"
local syntax = require "core.syntax"

---Functionality to tokenize source code using syntax definitions.
---@class core.tokenizer
local tokenizer = {}

local bad_patterns = {}

local function push_token(t, type, text)
  if not text or #text == 0 then return end
  type = type or "normal"
  local prev_type = t[#t-1]
  local prev_text = t[#t]
  if prev_type and (prev_type == type or (prev_text:ufind("^%s*$") and type ~= "incomplete")) then
    t[#t-1] = type
    t[#t] = prev_text .. text
  else
    table.insert(t, type)
    table.insert(t, text)
  end
end


local function push_tokens(t, syn, pattern, full_text, find_results)
  if #find_results > 2 then
    -- We do some manipulation with find_results so that it's arranged
    -- like this:
    -- { start, end, i_1, i_2, i_3, …, i_last }
    -- Each position spans characters from i_n to ((i_n+1) - 1), to form
    -- consecutive spans of text.
    --
    -- Insert the start index at i_1 to make iterating easier
    table.insert(find_results, 3, find_results[1])
    -- Copy the ending index to the end of the table, so that an ending index
    -- always follows a starting index after position 3 in the table.
    table.insert(find_results, find_results[2] + 1)
    -- Then, we just iterate over our modified table.
    for i = 3, #find_results - 1 do
      local start = find_results[i]
      local fin = find_results[i + 1] - 1
      local type = pattern.type[i - 2]
        -- ↑ (i - 2) to convert from [3; n] to [1; n]
      if fin >= start then
        local text = full_text:usub(start, fin)
        push_token(t, syn.symbols[text] or type, text)
      end
    end
  else
    local start, fin = find_results[1], find_results[2]
    local text = full_text:usub(start, fin)
    push_token(t, syn.symbols[text] or pattern.type, text)
  end
end

-- State is a string of bytes, where the count of bytes represents the depth
-- of the subsyntax we are currently in. Each individual byte represents the
-- index of the pattern for the current subsyntax in relation to its parent
-- syntax. Using a string of bytes allows us to have as many subsyntaxes as
-- bytes can be stored on a string while keeping some level of performance in
-- comparison to a Lua table. The only limitation is that a syntax would not
-- be able to contain more than 255 patterns.
--
-- Lets say a state contains 2 bytes byte #1 with value `3` and byte #2 with
-- a value of `5`. This would mean that on the parent syntax at index `3` a
-- pattern subsyntax that matched current text was found, then inside that
-- subsyntax another subsyntax pattern at index `5` that matched current text
-- was also found.

-- Calling `push_subsyntax` appends the current subsyntax pattern index to the
-- state and increases the stack depth. Calling `pop_subsyntax` clears the
-- last appended subsyntax and decreases the stack.

local function retrieve_syntax_state(incoming_syntax, state)
  local current_syntax, subsyntax_info, current_pattern_idx, current_level =
    incoming_syntax, nil, (state and state:byte(1)) or 0, 1
  if
    current_pattern_idx > 0
    and
    current_syntax.patterns[current_pattern_idx]
  then
    -- If the state is not empty we iterate over each byte, and find which
    -- syntax we're using. Rather than walking the bytes, and calling into
    -- `syntax` each time, we could probably cache this in a single table.
    for i = 1, #state do
      local target = state:byte(i)
      if target ~= 0 then
        if current_syntax.patterns[target].syntax then
          subsyntax_info = current_syntax.patterns[target]
          current_syntax = type(subsyntax_info.syntax) == "table" and
            subsyntax_info.syntax or syntax.get(subsyntax_info.syntax)
          current_pattern_idx = 0
          current_level = i+1
        else
          current_pattern_idx = target
          break
        end
      else
        break
      end
    end
  end
  return current_syntax, subsyntax_info, current_pattern_idx, current_level
end

---Return the list of syntaxes used in the specified state.
---@param base_syntax table @The initial base syntax (the syntax of the file)
---@param state string @The state of the tokenizer to extract from
---@return table @Array of syntaxes starting from the innermost one
function tokenizer.extract_subsyntaxes(base_syntax, state)
  local current_syntax
  local t = {}
  repeat
    current_syntax = retrieve_syntax_state(base_syntax, state)
    table.insert(t, current_syntax)
    state = string.sub(state or "", 2)
  until #state == 0
  return t
end

local function report_bad_pattern(log_fn, syntax, pattern_idx, msg, ...)
  if not bad_patterns[syntax] then
    bad_patterns[syntax] = { }
  end
  if bad_patterns[syntax][pattern_idx] then return end
  bad_patterns[syntax][pattern_idx] = true
  log_fn("Malformed pattern #%d <%s> in %s language plugin.\n" .. msg,
            pattern_idx,
            syntax.patterns[pattern_idx].pattern or syntax.patterns[pattern_idx].regex,
            syntax.name or "unnamed", ...)
end

-- Should be used to set the state variable. Don't modify it directly.
local function set_subsyntax_pattern_idx(state, current_level, pattern_idx)
  local state_len = #state
  if current_level > state_len then
    return state .. string.char(pattern_idx)
  elseif state_len == 1 then
    return string.char(pattern_idx)
  else
    return ("%s%s%s"):format(
      state:sub(1, current_level - 1),
      string.char(pattern_idx),
      state:sub(current_level + 1)
    )
  end
end

local function push_subsyntax(incoming_syntax, current_level, state, entering_syntax, pattern_idx)
  state = set_subsyntax_pattern_idx(state, current_level, pattern_idx)
  current_level = current_level + 1
  local subsyntax_info = entering_syntax
  local current_syntax = type(entering_syntax.syntax) == "table"
    and entering_syntax.syntax or syntax.get(entering_syntax.syntax)
  local current_pattern_idx = 0
  return current_syntax, subsyntax_info, current_pattern_idx, current_level, state
end

local function pop_subsyntax(incoming_syntax, state, current_level)
  current_level = current_level - 1
  state = string.sub(state, 1, current_level)
  state = set_subsyntax_pattern_idx(state, current_level, 0)
  local current_syntax, subsyntax_info, current_pattern_idx, current_level2 =
    retrieve_syntax_state(incoming_syntax, state)
  return current_syntax, subsyntax_info, current_pattern_idx, current_level2, state
end

local function find_text(text, p, offset, at_start, close)
  local target, res = p.pattern or p.regex, { 1, offset - 1 }
  local p_idx = close and 2 or 1
  local code = type(target) == "table" and target[p_idx] or target
  if p.disabled then return end

  if p.whole_line == nil then p.whole_line = {} end
  if p.whole_line[p_idx] == nil then
    -- Match patterns that start with '^'
    p.whole_line[p_idx] = code:umatch("^%^") and true or false
    if p.whole_line[p_idx] then
      -- Remove '^' from the beginning of the pattern
      if type(target) == "table" then
        target[p_idx] = code:usub(2)
        code = target[p_idx]
      else
        p.pattern = p.pattern and code:usub(2)
        p.regex = p.regex and code:usub(2)
        code = p.pattern or p.regex
      end
    end
  end

  if p.regex and type(p.regex) ~= "table" then
    p._regex = p._regex or regex.compile(p.regex)
    code = p._regex
  end

  repeat
    local next = res[2] + 1
    -- If the pattern contained '^', allow matching only the whole line
    if p.whole_line[p_idx] and next > 1 then
      return
    end
    res = p.pattern and { text:ufind((at_start or p.whole_line[p_idx]) and "^" .. code or code, next) }
      or { regex.find(code, text, text:ucharpos(next), (at_start or p.whole_line[p_idx]) and regex.ANCHORED or 0) }
    if p.regex and #res > 0 then
      local char_pos_1 = res[1] > next and string.ulen(text:sub(1, res[1]), nil, nil, true) or next
      local char_pos_2 = string.ulen(text:sub(1, res[2]), nil, nil, true)
      for i = 3, #res do
        res[i] = string.ulen(text:sub(1, res[i] - 1), nil, nil, true) + 1
      end
      res[1] = char_pos_1
      res[2] = char_pos_2
    end
    if not res[1] then return end
    if res[1] and target[3] then
      -- Check to see if the escaped character is there,
      -- and if it is not itself escaped.
      local count = 0
      for i = res[1] - 1, 1, -1 do
        if text:ubyte(i) ~= target[3]:ubyte() then break end
        count = count + 1
      end
      if count % 2 == 0 then
        -- The match is not escaped, so confirm it
        break
      else
        -- The match is escaped, so avoid it
        res[1] = false
      end
    end
  until at_start or not close or not target[3]
  return table.unpack(res)
end

---@param incoming_syntax table
---@param text string
---@param state string
function tokenizer.tokenize(incoming_syntax, text, state, resume)
  local res
  local i = 1

  state = state or string.char(0)

  if #incoming_syntax.patterns == 0 then
    return { "normal", text }, state
  end

  if resume then
    res = resume.res
    -- Remove "incomplete" tokens
    while res[#res - 1] == "incomplete" do
      table.remove(res)
      table.remove(res)
    end
    i = resume.i
    state = resume.state
  end

  res = res or {}

  -- incoming_syntax    : the parent syntax of the file.
  -- state              : a string of bytes representing syntax state (see above)

  -- current_syntax     : the syntax we're currently in.
  -- subsyntax_info     : info about the delimiters of this subsyntax.
  -- current_pattern_idx: the index of the pattern we're on for this syntax.
  -- current_level      : how many subsyntaxes deep we are.
  local current_syntax, subsyntax_info, current_pattern_idx, current_level =
    retrieve_syntax_state(incoming_syntax, state)

  local text_len = text:ulen(nil, nil, true)
  local start_time = system.get_time()
  local starting_i = i
  local max_time = math.floor(10000 * (core.co_max_time / 2)) / 10000
  while i <= text_len do
    -- Every 200 chars, check if we're out of time
    if text_len > 200 or i - starting_i > 200 then
      starting_i = i
      if system.get_time() - start_time > max_time then
        -- We're out of time
        push_token(res, "incomplete", string.usub(text, i))
        return res, string.char(0), {
          res = res,
          i = i,
          state = state
        }
      end
    end
    -- continue trying to match the end pattern of a pair if we have a state set
    if current_pattern_idx > 0 then
      local p = current_syntax.patterns[current_pattern_idx]
      local find_results = { find_text(text, p, i, false, true) }
      local s, e = find_results[1], find_results[2]
      -- Use the first token type specified in the type table for the "middle"
      -- part of the subsyntax.
      local token_type = type(p.type) == "table" and p.type[1] or p.type

      local cont = true
      -- If we're in subsyntax mode, always check to see if we end our syntax
      -- first, before the found delimeter, as ending the subsyntax takes
      -- precedence over ending the delimiter in the subsyntax.
      if subsyntax_info then
        local ss, se = find_text(text, subsyntax_info, i, false, true)
        -- If we find that we end the subsyntax before the
        -- delimiter, push the token, and signal we shouldn't
        -- treat the bit after as a token to be normally parsed
        -- (as it's the syntax delimiter).
        if ss and (s == nil or ss < s) then
          push_token(res, token_type, text:usub(i, ss - 1))
          i = ss
          cont = false
        end
      end
      -- If we don't have any concerns about syntax delimiters,
      -- continue on as normal.
      if cont then
        if s then
          -- Push remaining token before the end delimiter
          if s > i then
            push_token(res, token_type, text:usub(i, s - 1))
          end
          -- Push the end delimiter
          push_tokens(res, current_syntax, p, text, find_results)
          current_pattern_idx = 0
          state = set_subsyntax_pattern_idx(state, current_level, 0)
          i = e + 1
        else
          push_token(res, token_type, text:usub(i))
          break
        end
      end
    end
    -- General end of syntax check. Applies in the case where
    -- we're ending early in the middle of a delimiter, or
    -- just normally, upon finding a token.
    while subsyntax_info do
      local find_results = { find_text(text, subsyntax_info, i, true, true) }
      local s, e = find_results[1], find_results[2]
      if s then
        push_tokens(res, current_syntax, subsyntax_info, text, find_results)
        -- On finding unescaped delimiter, pop it.
        current_syntax, subsyntax_info, current_pattern_idx, current_level, state =
          pop_subsyntax(incoming_syntax, state, current_level)
        i = e + 1
      else
        break
      end
    end

    -- find matching pattern
    local matched = false
    for n, p in ipairs(current_syntax.patterns) do
      local find_results = { find_text(text, p, i, true, false) }
      if find_results[1] then
        -- Check for patterns successfully matching nothing but allows
        -- those that delegate the result to a subsyntax
        if find_results[1] > find_results[2] and not p.syntax then
          report_bad_pattern(core.warn, current_syntax, n,
            "Pattern successfully matched, but nothing was captured.")
        -- Check for patterns with mismatching number of `types`
        else
          local type_is_table = type(p.type) == "table"
          local n_types = type_is_table and #p.type or 1
          if #find_results == 2 and type_is_table then
            report_bad_pattern(core.warn, current_syntax, n,
              "Token type is a table, but a string was expected.")
            p.type = p.type[1]
          elseif #find_results - 1 > n_types then
            report_bad_pattern(core.error, current_syntax, n,
              "Not enough token types: got %d needed %d.", n_types, #find_results - 1)
          elseif #find_results - 1 < n_types then
            report_bad_pattern(core.warn, current_syntax, n,
              "Too many token types: got %d needed %d.", n_types, #find_results - 1)
          end

          -- matched pattern; make and add tokens
          push_tokens(res, current_syntax, p, text, find_results)
          -- update state if this was a start|end pattern pair
          if type(p.pattern or p.regex) == "table" then
            -- If we have a subsyntax, push that onto the subsyntax stack.
            if p.syntax then
              current_syntax, subsyntax_info, current_pattern_idx, current_level, state =
                push_subsyntax(incoming_syntax, current_level, state, p, n)
            else
              current_pattern_idx = n
              state = set_subsyntax_pattern_idx(state, current_level, n)
            end
          end
          -- move cursor past this token
          i = find_results[2] + 1
          matched = true
          break
        end
      end
    end

    -- consume character if we didn't match
    if not matched then
      push_token(res, "normal", text:usub(i, i))
      i = i + 1
    end
  end

  return res, state
end


local function token_iter(state, i)
  i = i + 2
  if i > state.tcount then return nil end
  local type, text = state.t[i], state.t[i + 1]
  if state.col then
    text = string.sub(text, state.col)
    state.col = nil -- slice only once
  end
  return i, type, text
end

---Iterator for a sequence of tokens in the form {type, token, ...},
---returning each pair of token type and token string.
---@param t string[] List of tokens in the form {type, token, ...}
---@param scol? integer The starting offset of all combined tokens.
---@return fun(state,idx):integer,string,string iterator
---@return table state
---@return integer idx
function tokenizer.each_token(t, scol)
  local tcount, start, col = #t, 1, nil
  if scol then
    local ccol = 1
    for i=1, tcount, 2 do
      local text = t[i+1]
      local len = #text
      if scol <= (ccol + len - 1) then
        start = i
        col = scol - ccol + 1
        break
      end
      ccol = ccol + len + 1
    end
  end
  local state = {t = t, tcount = tcount, col = col}
  return token_iter, state, start - 2
end


return tokenizer
