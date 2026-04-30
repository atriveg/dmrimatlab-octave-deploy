function dmrimatlab_save_cmd_args(outs,fouts,hdr)
  for n=1:length(outs)
    save_single_out( outs(n), fouts{n}, hdr );
  end
end

% -------------------------------------------
function save_single_out(out,fout,hdr)
  fname = out.value;
  if(isempty(fname))
    return;
  end
  fname   = strtrim(fname);
  if(strcmp(fname,'print'))
    disp(fout);
    return;
  end
  pattern = '.*\.(nii\.gz|nii|bvals|bvecs|bval|bvec|mat|txt|dat)';
  tokens  = regexp( fname, pattern, 'tokens');
  if(isempty(tokens))
    error('Unable to determine the extension of outputfile %s',fname);
  end

  switch(tokens{1}{1})
    case {'nii.gz','nii'}
      % In case the volume to save is boolean, we need to convert
      % since it is not supported by nifti:
      if(islogical(fout))
        fout = uint8(255*fout);
      end
      saveniiasin( fout, fname, hdr );
    case {'bvals','bval','bvecs','bvec','txt','dat'}
      dlmwrite( fname, fout, 'delimiter', ' ', 'newline', '\n', 'precision', 15);
    case {'mat'}
      save(fname,'fout');
    otherwise
      error('%s: I cannot write an output file with extension %s',fname,tokens{1}{1});
  end
end



