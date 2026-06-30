function [iargs,hdr] = dmrimatlab_interpret_cmd_args(args,cmdstr,gargs)
iargs.inputs = [];
iargs.outputs = [];
gi = [];
bi = [];
hdr = [];

    function intrpd = interpret_single_arg(arg,flag,name)
        if(nargin<3)
            name = '';
        end
        intrpd = arg;
        % If this is an input or an optional argument, we must
        % either interpret the Octave string or load a file.
        if(flag<2)
            if(~strcmp(arg.argtype,'string'))
                [intrpd.value,hdr_,gi_,bi_] = load_actual_data(arg.value);
            else
                hdr_ = [];
                gi_  = [];
                bi_  = [];
            end
            % If a nifti header has not been set yet, use
            % the current one:
            if(isempty(hdr))
                hdr = hdr_;
            end
            % The same goes for gi and bi:
            if(isempty(gi))
                gi = gi_;
            end
            if(isempty(bi))
                bi = bi_;
            end
            % Now, try to guess the argument type in case it was
            % not explicitly provided:
            if(isempty(arg.argtype))
                intrpd.argtype = determine_arg_type(arg,size(intrpd.value),name,cmdstr);
            end
            % Finally, check the argument type is a proper one:
            switch(intrpd.argtype)
                case {'vec','sh','dwi','atti','dti','vol','raw','coeff','string','UNK'}
                    % Nothing to do
                case 'bval'
                    intrpd.value = intrpd.value(:);
                    if(~ismatrix(intrpd.value))
                        error('%s was interpreted as a b-values description, but it is not a vector',arg.value);
                    end
                    if(size(intrpd.value,2)~=1)
                        intrpd.value = intrpd.value';
                    end
                    if(size(intrpd.value,2)~=1)
                        error('%s was interpreted as a b-values description, but it is not a vector',arg.value);
                    end
                    if(isempty(bi))
                        bi = intrpd.value;
                        if(~isempty(gi))
                            assert( size(gi,1)==size(bi,1), 'You provided files with b-vectors and b-values whose dimensions are not consistent' );
                        end
                    end
                case 'bvec'
                    if(~ismatrix(intrpd.value))
                        error('%s was interpreted as a gradients table, but it is not a matrix',arg.value);
                    end
                    if(size(intrpd.value,2)~=3)
                        intrpd.value = intrpd.value';
                    end
                    if(size(intrpd.value,2)~=3)
                        error('%s was interpreted as a gradients table, but it is not a Gx3 matrix',arg.value);
                    end
                    if(isempty(gi))
                        gi = intrpd.value;
                        if(~isempty(bi))
                            assert( size(gi,1)==dize(bi,1), 'You provided files with b-vectors and b-values whose dimensions are not consistent' );
                        end
                    end
                case 'nrrd_gi'
                    % This is an input with the gradient directions, and it should be
                    % taken directly from a NRRD file that should have been read before
                    % and parsed to obtain the variable "gi"
                    intrpd.value = gi;
                case 'nrrd_bi'
                    % This is an input with the gradient b-values, and it should be
                    % taken directly from a NRRD file that should have been read before
                    % and parsed to obtain the variable "bi"
                    intrpd.value = bi;
                case 'mask'
                    intrpd.value = (intrpd.value>0.1);
                otherwise
                    error('You provided argument type <%s>, which is unrecognized',intrpd.argtype);
            end
        end
        % If this is an output, we cannot write it yet, so we
        % just make sure the value is some file we can write
        % things to
        if(flag>1)
            check_valid_extension(arg.value);
        end

    end

% Begin with the inputs, which are always present:
for n=1:length(args.inputs)
    iargs.inputs(n) = interpret_single_arg( args.inputs(n), 0 );
end
% Then, the outputs:
for n=1:length(args.outputs)
    iargs.outputs(n) = interpret_single_arg( args.outputs(n), 2 );
end
% Then, the remaining fields of the structure:
fields = fieldnames(args);
fields = fields( ~strcmp(fields,'inputs') );
fields = fields( ~strcmp(fields,'outputs') );
for n=1:length(fields)
    field = fields{n};
    iargs.(field) = interpret_single_arg( args.(field), 1, field );
end
% Then, all fields of the global options structure:
fields = fieldnames(gargs);
for n=1:length(fields)
    field = fields{n};
    gargs.(field) = interpret_single_arg( gargs.(field), 1, field );
end
% ------------------------------------------------------------------
% We're almost there. However, some inputs and/or optional arguments
% are very likely either DWI channels or attenuation signals. We
% have to post-proces them because:
%  - It might be the needed to prune gradient tables.
%  - It might be needed to convert DWIs to attenuations.

% First, prune all DWI/atti channels that won't be used in any case:
[iargs,gi,bi] = prune_dwichannels(  iargs, gi, bi, gargs.g_b0th.value, gargs.g_bmin.value, gargs.g_bmax.value );
[iargs,gi,bi] = prune_attichannels( iargs, gi, bi, gargs.g_bmin.value, gargs.g_bmax.value );
% Now, depending on the kind of command we deal with, convert DWI->atti
if( strncmp(cmdstr,'atti2',5) )
    % Need to convert
    [iargs,gi,bi] = convert_dwi2atti( iargs, gi, bi, gargs.g_b0th.value );
elseif( strncmp(cmdstr,'dwi2',4) )
    % We are all done
else
    % Other commands taking DWI/att-like inputs are assumed
    % to  work with attenuation signals, so we do the same
    % as we did eith the atti2 case.
    [iargs,gi,bi] = convert_dwi2atti( iargs, gi, bi, gargs.g_b0th.value );
end
iargs = fix_gradient_tables( iargs, gi, bi );

end

%% -----------------------------------------------------------------------------
function [value,hdr,gi,bi] = load_actual_data(istring)
hdr = [];
gi  = [];
bi  = [];
if(isempty(istring))
    value = [];
    return;
end
pattern = '.*\.(nii\.gz|nii|nhdr|nrrd|bvals|bvecs|bval|bvec|mat|txt|dat)$';
istring = strtrim(istring);
tokens  = regexp( istring, pattern, 'tokens');
if(isempty(tokens))
    % Check if this is a keyword to force the gradients table
    % to be read from a NRDD file:
    if( strcmpi(istring,'nrrd:gi') || strcmpi(istring,'nrrd:bi') )
        % It is, indeed. Just exit:
        value = [];
        return;
    end
    % Otherwise, assume this is just a expression to evaluate in octave:
    try
        value = eval(istring);
    catch
        error('I was unable to process <%s> as a valid Octave string. In case it is a file, please set a proper extension for it',istring);
    end
else
    % This is a file that needs to be processed
    switch(tokens{1}{1})
        case {'nii.gz','nii'}
            % ------------------------------------------
            % This is a nifti file that we can load:
            hdr.nii   = niiRead(istring);
            hdr.nrrd  = [];
            hdr.space = 'RAS';
            hdr.T     = [ hdr.nii.hdr.hist.srow_x; hdr.nii.hdr.hist.srow_y; hdr.nii.hdr.hist.srow_z; [0,0,0,1] ];
            % ------------------------------------------
            value     = hdr.nii.img;
            hdr.nii.img = [];
        case {'nhdr','nrrd'}
            % ------------------------------------------
            % This is a nrrd file that we can load:
            hdr.nrrd   = nrrdLoad(istring);
            hdr.nii    = [];
            if(isfield(hdr.nrrd.metaData,'space'))
                hdr.space = nrrd_trim_space(hdr.nrrd.metaData.space);
            else
                hdr.space = 'LPS';
            end
            hdr.T      = hdr.nrrd.ijkToLpsTransform;
            % ------------------------------------------
            value      = hdr.nrrd.pixelData;
            hdr.nrrd.pixelData = [];
            % NOTE: if the volume has more than 3 dimensions, we
            % need to internally represent it with the spatial
            % domains in the last three positions, but this is
            % not necessarily the way NRRD will work:
            value = permute_nrrd_dims(value,hdr.nrrd);
            % If this is a DWI volume, retrieve the gradients table:
            if(   ( isfield(hdr.nrrd.metaData,'modality') && strcmp(hdr.nrrd.metaData.modality,'DWMRI') ) || isfield(hdr.nrrd.metaData,'DWMRI_b_value')   )
                [gi,bi] = get_nrrd_gradients(hdr.nrrd.metaData);
            end
        case {'bvals','bval','bvecs','bvec','txt','dat'}
            value   = load(istring);
        case {'mat'}
            data    = load(istring);
            fnames  = fieldnames(data);
            if(length(fnames)<1)
                error('%s seems to be empty',istring);
            end
            if(length(fnames)>1)
                warning('%s contains several variables. Only the first one will be used',istring);
            end
            value   = data.(fnames{1});
        otherwise
            error('%s: I cannot read a file with extension %s',istring,tokens{1}{1});
    end
end
end

%% -----------------------------------------------------------------------------
function atype = determine_arg_type(arg,szs,name,cmdstr)
if(isempty(arg.value))
    atype = 'UNK';
    return;
end
if(strcmp(name,'mask'))
    atype = 'mask';
    return;
end
pattern = '.*\.(nii\.gz|nii|nhdr|nrrd|bvals|bvecs|bval|bvec|mat|txt|dat)$';
istring = strtrim(arg.value);
tokens  = regexp( istring, pattern, 'tokens');
if(isempty(tokens))
    % Check if this is a keyword to force the gradients table
    % to be read from a NRDD file:
    if( strcmpi(istring,'nrrd:gi') || strcmpi(istring,'nrrd:bi') )
        % It is, indeed:
        atype =  strrep( lower(istring), ':', '_' );
        return;
    end
    % Otherwise, assume this is just a expression to evaluate in octave
    atype = 'UNK';
else
    % This is a file that needs to be processed
    switch(tokens{1}{1})
        case {'nii.gz','nii','nhdr','nrrd','mat'}
            switch(length(szs))
                case 3
                    atype = 'vol';
                case 4
                    if(szs(4)==3)
                        atype = 'vec';
                    elseif(szs(4)==6)
                        if(strncmp(cmdstr,'atti2',5))
                            atype = 'atti';
                        elseif(strncmp(cmdstr,'sh2',3))
                            atype = 'sh';
                        elseif(strncmp(cmdstr,'mapl2',5))
                            atype = 'coeff';
                        elseif(strncmp(cmdstr,'hydidsi2',8))
                            atype = 'coeff';
                        else
                            atype = 'dti';
                        end
                    else
                        % This is the most difficult case, since the volume
                        % might be a dwi, a dwi that has to be interpreted as
                        % an atti or an sh volume. In case the function is
                        % atti2- or dwi2-like, it is likely that a nifti file
                        % has been passed with raw DWI channels. In case it
                        % is sh2-like, it is likely that a SH volume was passed.
                        if(strncmp(cmdstr,'atti2',5))
                            atype = 'dwi';
                        elseif(strncmp(cmdstr,'dwi2',4))
                            atype = 'dwi';
                        elseif(strncmp(cmdstr,'sh2',3))
                            atype = 'sh';
                        elseif(strncmp(cmdstr,'mapl2',5))
                            atype = 'coeff';
                        elseif(strncmp(cmdstr,'hydidsi2',8))
                            atype = 'coeff';
                        else
                            atype = 'dwi';
                        end
                    end
                case 5
                    if( (szs(4)==3) && (szs(5)==3) )
                        atype = 'dti';
                    else
                        atype = 'UNK';
                    end
                otherwise
                    atype = 'UNK';
            end
        case {'bvals','bval'}
            atype = 'bval';
        case {'bvecs','bvec'}
            atype = 'bvec';
        case {'txt','dat'}
            atype = 'UNK';
    end
end
end

%% -----------------------------------------------------------------------------
function check_valid_extension(istring)
if(isempty(istring))
    return;
end
istring = strtrim(istring);
if( isempty(istring) )
    return;
end
pattern = '(print)($|\{([^\}]*)\})';
tokens  = regexp( istring, pattern, 'tokens');
if( ~isempty(tokens) )
    return;
end
pattern = '.*\.(nii\.gz|nii|nhdr|nrrd|bvals|bvecs|bval|bvec|mat|txt|dat)$';
tokens  = regexp( istring, pattern, 'tokens');
if( isempty(tokens) )
    error('All requested outputs must be written to a file, but you provided %s, which has not a valid extension',istring);
end
end


%% -----------------------------------------------------------------------------
function [args,gi,bi] = prune_dwichannels(args,gi0,bi0,b0th,bmin,bmax)
gi = gi0;
bi = bi0;
for n=1:length(args.inputs)
    if(strcmp(args.inputs(n).argtype,'dwi'))
        if( isempty(bi0) )
            error('Some of the inputs have been detected as DWI signals, but a b-values description was not found');
        end
        pp = ( (bi<=b0th) |  ( (bi>=bmin) & (bi<=bmax) ) );
        if( ~isempty(gi) )
            gi = gi(pp,:);
        end
        bi = bi(pp,:);
        args.inputs(n).value = args.inputs(n).value(:,:,:,pp);
    end
end
end

%% -----------------------------------------------------------------------------
function [args,gi,bi] = prune_attichannels(args,gi0,bi0,bmin,bmax)
gi = gi0;
bi = bi0;
for n=1:length(args.inputs)
    if(strcmp(args.inputs(n).argtype,'atti'))
        if( isempty(bi0) )
            error('Some of the inputs have been detected as attenuation signals, but a b-values description was not found');
        end
        pp = ( (bi>=bmin) & (bi<=bmax) );
        if( ~isempty(gi) )
            gi = gi(pp,:);
        end
        bi = bi(pp,:);
        args.inputs(n).value = args.inputs(n).value(:,:,:,pp);
    end
end
end

%% -----------------------------------------------------------------------------
function [args,gi,bi] = convert_dwi2atti(args,gi0,bi0,b0th)
gi = gi0;
bi = bi0;
for n=1:length(args.inputs)
    if(strcmp(args.inputs(n).argtype,'dwi'))
        if( isempty(bi0) || isempty(gi0) )
            error('Some of the inputs need conversion to atti signals, but a full gradients table was not found');
        end
        [args.inputs(n).value,gi,bi] = dwi2atti(args.inputs(n).value,gi0,bi0,'b0th',b0th);
        args.inputs(n).argtype = 'atti';
    end
end
end

%% -----------------------------------------------------------------------------
function args = fix_gradient_tables( args, gi, bi )
for n=1:length(args.inputs)
    if( strcmp(args.inputs(n).argtype,'bvec') || strcmp(args.inputs(n).argtype,'nrrd_gi') )
        args.inputs(n).value = gi;
    end
    if( strcmp(args.inputs(n).argtype,'bval') || strcmp(args.inputs(n).argtype,'nrrd_bi') )
        args.inputs(n).value = bi;
    end
end
end

%% -----------------------------------------------------------------------------
function img = permute_nrrd_dims(img,nrrd)
if(ndims(img)<4)
    return;
end
strs  = strsplit(nrrd.metaData.kinds);
mtchs = strfind(strs,'domain');
if( isempty([mtchs{:}]) )
    mtchs = strfind(strs,'space');
    if( isempty([mtchs{:}]) )
        error('Misformed kinds string in NRRD file: %s',nrrd.metaData.kinds);
    end
end
pos = false( 1, length(mtchs) );
for d=1:length(mtchs)
    pos(d) = ~isempty(mtchs{d});
end
if(sum(pos)~=3)
    error('Misformed kinds string in NRRD file: %s',nrrd.metaData.kinds);
end
anat = find(pos);
lsts = setdiff( 1:ndims(img), anat );
idx  = [anat,lsts];
img  = permute(img,idx);
end

%% -----------------------------------------------------------------------------
function [gi,bi] = get_nrrd_gradients(metaData)
bi = [];
gi = [];
if(isfield(metaData,'DWMRI_b_value'))
    b0 = str2double(metaData.DWMRI_b_value);
else
    b0 = 1000;
end
if(isfield(metaData,'measurement_frame'))
    mfstr  = regexprep(metaData.measurement_frame,'\s','');
    mfstr  = regexprep(mfstr,'\)\(','\) \(');
    mframe = reshape(sscanf(mfstr,'(%f,%f,%f) (%f,%f,%f) (%f,%f,%f)'),3,3);
else
    mframe = eye(3);
end
fns    = sort(fieldnames(metaData));
for n=1:length(fns)
    idx = strfind(fns{n},'DWMRI_gradient');
    if(~isempty(idx))
        grad = sscanf( metaData.(fns{n}), '%f %f %f' );
        if(length(grad)~=3)
            error('Misformed DWMRI_gradient in NRRD file: %s',metaData.(fns{n}));
        end
        gi = [gi;grad']; %#ok<AGROW>
    end
end
% Normalize according to:
%
% https://www.na-mic.org/wiki/NAMIC_Wiki:DTI:Nrrd_format#Describing_DWIs_with_different_b-values
%
% NOTE: Accroding to vtkMRMLNRRDStorageNode::ParseDiffusionInformation(),
%       each bi is computed as:
%
%          bi = b0*( ||gi|| / max_i{||gi||} )^2,
%
%       where b0 is the reference value passed with the DWMRI_b-value tag
if(~isempty(gi))
    ni = sqrt(sum(gi.*gi,2));
    ni = ni/max(ni);
    bi = b0*ni.*ni;
    gi(ni>0) = gi(ni>0)./ni(ni>0);
end
% Finally, correct the gradient directions according to the measurement
% frame:
gi = gi*(mframe');
end

%% -----------------------------------------------------------------------------
function space = nrrd_trim_space(space)
if(length(space)==3)
    space = upper(space);
    return;
end
pattern = '\s*(right|left)-(anterior|posterior)-(inferior|superior)\s*';
tokens  = regexp( space, pattern, 'tokens');
if(isempty(tokens))
    error('Misformed space string in NRRD file: %s',space);
end
s1    = tokens{1}{1};
s2    = tokens{1}{2};
s3    = tokens{1}{3};
space = upper([s1(1),s2(1),s3(1)]);
end
