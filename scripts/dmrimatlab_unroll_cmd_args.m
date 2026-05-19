function [uargs,outs] = dmrimatlab_unroll_cmd_args(args)
  outs  = args.outputs;
  uargs = {};

  k=1;

  for n=1:length(args.inputs)
    uargs{k} = args.inputs(n).value;
    k = k+1;
  end

  fields = fieldnames(args);
  fields = fields( ~strcmp(fields,'inputs') );
  fields = fields( ~strcmp(fields,'outputs') );
  for n=1:length(fields)
    field = fields{n};
    uargs{k}   = field;
    uargs{k+1} = args.(field).value;
    k = k+2;
  end

end
