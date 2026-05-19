function [largs,gargs] = dmrimatlab_parse_cmd_args(args)
  % Initialize the output structures
  [largs,gargs] = init_parse_structures;

  % Regular expressions to validate the allowed formats:
  %
  % -input[ordinal][:argtype]=value
  % -output[ordinal][:argtype]=value
  % -optionalkey[:argtype]=value

  pattern1 = '^-(input|output)([0-9]*)(:.*)?=(.*)$';
  %pattern2 = '^-([a-zA-Z]+)([0-9]*)(\[.*\])?=(.*)$';
  pattern2 = '^-([^=\[\]:]+)(:.*)?=(.*)$';

  for i = 1:length(args)
    arg    = strtrim(args{i});

    % Try to process as either an input or an output
    tokens = regexp(arg, pattern1, 'tokens');
    if(~isempty(tokens))
      % If tokens is not empty, then this is actually an I/O:
      % Extract the captured groups
      % tokens{1} = {name, ordinal, argtype, value}
      parts    = tokens{1};
      arg_name = parts{1};
      ordinal  = str2double(parts{2}); % Results in NaN if empty
      % In case no argtype [] were passed, only 3 parts are returned,
      % the third one being the value itself:
      if(length(parts)<4)
        argtype = '';
        val     = parts{3};
      else
        argtype = parts{3};
        val     = parts{4};
      end
    else
      % This seems to be an optional key/value pair. Try to parse:
      tokens = regexp(arg, pattern2, 'tokens');
      % If it doesn't match the required format, throw an error
      if isempty(tokens)
        error('Invalid argument: "%s". Must follow the format -name[#][:argtype]=value', arg);
      end
      % Otherwise, extract the captured groups:
      parts    = tokens{1};
      arg_name = strtrim(parts{1});
      % In case no argtype [] were passed, only 2 parts are returned,
      % the third one being the value itself:
      if(length(parts)<3)
        argtype = '';
        val     = parts{2};
      else
        argtype = parts{2};
        val     = parts{3};
      end
    end

    % Remove the : from argtype if it exists
    if ~isempty(argtype)
      argtype = argtype(2:end);
    end

    switch arg_name
      case 'input'
        idx = length(largs.inputs) + 1;
        largs.inputs(idx).value = val;
        largs.inputs(idx).argtype = argtype;
        largs.inputs(idx).ordinal = ordinal;

      case 'output'
        idx = length(largs.outputs) + 1;
        largs.outputs(idx).value = val;
        largs.outputs(idx).argtype = argtype;
        largs.outputs(idx).ordinal = ordinal;

      otherwise
        % For "other" arguments, create a dynamic field using the argument name
        % Note: Field names in Octave must be valid identifiers (no special chars)
        if( strncmp(arg_name,'g_',2) )
          gargs.(arg_name).value   = val;
          gargs.(arg_name).argtype = argtype;
        else
          largs.(arg_name).value   = val;
          largs.(arg_name).argtype = argtype;
        end
    end
  end

  % Pay attention to the ordering of I/O so that we no longer have to care about it:
  largs = fix_ordinals(largs);

end

%% -----------------------------------------------------------------------------
function [largs,gargs] = init_parse_structures
  largs.inputs = [];
  largs.outputs = [];
  gargs.g_b0th.value = '1';
  gargs.g_b0th.argtype = 'UNK';
  gargs.g_bmin.value = '0';
  gargs.g_bmin.argtype = 'UNK';
  gargs.g_bmax.value = 'Inf';
  gargs.g_bmax.argtype = 'UNK';
  gargs.g_log.value = '';
  gargs.g_log.argtype = 'UNK';
end

%% -----------------------------------------------------------------------------
function iargs = fix_ordinals(iargs)

  function fix_IO_iordinals(io_kind)
    iord = [iargs.(io_kind).ordinal];
    if( any(isnan(iord)) )
      if( ~all(isnan(iord)) )
        error('You have provided ordinals for certain %s but not for others, which is ambiguous',io_kind);
      end
    else
      % Ordering has been provided "by hand"
      if( ~isequal(sort(iord),unique(iord)) )
        error('You have provided reapeated ordinals for several %s',io_kind);
      end
      % How many indices do we have?
      NI = max(iord);
      % Create as many structures as indices:
      ios = struct('value',[],'argtype','UNK','ordinal',NaN);
      ios(1:NI+1) = ios;
      ios(iord+1) = iargs.(io_kind);
      iargs.(io_kind) = ios;
      % Note ordinal is no longer needed
    end
  end

  fix_IO_iordinals('inputs');
  fix_IO_iordinals('outputs');

end
