function dmrimatlab_save_cmd_args(outs,fouts,hdr)
if(~isfield(hdr,'T'))
    hdr.T = eye(4);
end
if(~isfield(hdr,'space'))
    hdr.space = 'RAS';
end
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

% Check if this is an output that needs to be printed:
pattern = '(print)($|\{([^\}]*)\})';
tokens  = regexp( fname, pattern, 'tokens' );
if(~isempty(tokens))
    % It is, indeed
    % Check if the user provided a name for the output:
    if(~isempty(tokens{1}{2}))
        if(~isempty(tokens{1}{3}))
            % He did:
            fprintf(1,'%s = ',tokens{1}{3});
        end
    end
    disp(fout);
    return;
end

pattern = '.*\.(nii\.gz|nii|nhdr|nrrd|bvals|bvecs|bval|bvec|mat|txt|dat)';
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
        % The way we will save the volume depends on the kind
        % of header we have:
        if(~isempty(hdr.nii))
            % We can use this header directly:
            niiSaveAsIn( fout, fname, hdr.nii );
        else
            % We need to create an ad-hoc header. First,
            % check if the space is ras, otherwise we need
            % to convert:
            needToInvert = ( hdr.space == 'LPI' );
            hdr.T(needToInvert,:) = -hdr.T(needToInvert,:);
            nii = niiMakeHdr( fout, hdr.T, [], 'Created with dmrimatlab-deploy' );
            niiWrite( nii, fname );
        end
    case {'nhdr','nrrd'}
        if(islogical(fout))
            fout = uint8(255*fout);
        end
        % NOTE: if the volume has more than 3 dimensions, it
        % is internally represented as X x Y x Z x N_1 x N_2 x ...
        % but the NRRD I/O functions expect it the other way
        % around:
        nd = ndims(fout);
        if(nd>3)
            idx  = [4:nd,1:3];
            fout = permute(fout,idx);
        end
        % The way we will save the volume depends on the kind
        % of header we have:
        if(~isempty(hdr.nrrd))
            % We can use this header directly:
            nrrdSaveAsIn( fout, fname, hdr.nrrd );
        else
            % We need to create an ad-hoc header:
            nrrd = nrrdMakeHdr( fout, hdr.T, hdr.space, [] );
            nrrd.description = 'Created with dmrimatlab-deploy';
            nrrdSave( nrrd, fname );
        end
    case {'bvals','bval','bvecs','bvec','txt','dat'}
        dlmwrite( fname, fout, 'delimiter', ' ', 'newline', '\n', 'precision', 15);
    case {'mat'}
        save(fname,'fout');
    otherwise
        error('%s: I cannot write an output file with extension %s',fname,tokens{1}{1});
end
end
