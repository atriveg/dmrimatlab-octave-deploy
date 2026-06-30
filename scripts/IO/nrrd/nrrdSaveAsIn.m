function nrrd = nrrdSaveAsIn( vol, nrrdfilename, template )
% function nrrd = nrrdSaveAsIn( vol, nrrdfilename, template )
%
% This function is intended to ease the writing of data volumes processed
% by the toolbox to nrrd files that can be read and displayed by some
% other software. In brief:
%
%    vol: is a X x Y x Z or a X x Y x Z x W 3-D or 4-D array coming from a
%        certain processing pipeline (for example: a FA map, a denoised DWI
%        volume, a volume containing spherical harmonic coefficients...).
%
%    nrrdfilename: is the filename of the nrrd file to be written.
%
%    template: is either a structure as returned by "nrrdLoad" or
%        the name of a nrrd file (with extension .nrrd or .nhdr) whose
%        anatomical information matches that of <vol>.
%
%    nrrd: is the nrrd structure to be written to nrrdfilename, virtually
%        identical to the result of running:
%            >> nrrd = nrrdLoad(nrrdfilename)
%
%    EXAMPLE: Imagine you have a DWI volume in a nrdd file named
%    'dwi.nrrd'. Then you can extract its first channel to a new nrrd
%    file as follows:
%
%       >> dwi = nrrdLoad('dwi.nrrd');
%       >> first = dwi.img(:,:,:,1);
%       >> nrrdSaveAsIn( first, 'firstchannel.nrrd', dwi );
%
%     Alterantively, the last line can also read:
%
%       >> nrrdSaveAsIn( first, 'firstchannel.nrrd', 'dwi.nrrd' );
%
%     but it will take longer since it will have to read 'dwi.nrrd'
%     again.
%
% NOTE: if vol is N-D, with D>3, the function assumes that the anatomical
%       dimensions (X,Y,Z) are the last non-singleton dimensions

if(nargin~=3)
    error('Supply just the data volume, the file name and a template');
end

if(ischar(template))
    try
        template = nrrdLoad(template);
    catch ME
        warning('Could not open nii file <%s>',template);
        rethrow(ME);
    end
end

% Create nrrd structure:
nrrd = replicate_nrrd_struct(vol, template);

% Save nrrd file:
try
    nrrdSave(nrrd,nrrdfilename);
catch ME
    warning('Could not save nii file <%s>',nrrdfilename);
    rethrow(ME);
end

end

% -------------------------------------------------------------------------
function nrrd = replicate_nrrd_struct(vol, template )
% Initalize the output the sane as the template:
nrrd = template;
nrrd.pixelData = vol;
nrrd.metaData.type = getMetaType(class(vol));
% ------------------------------------------------------
% Check the number of dimensions
nd = max(ndims(vol),3);
if( nd>5 )
    error('The input volume has an unsupported number of dimensions');
end
X   = size( vol, nd-2 );
Y   = size( vol, nd-1 );
Z   = size( vol, nd-0 );
pad = zeros(1,nd-3);
for d=1:nd-3
    pad(d) = size(vol,d);
end
nrrd.metaData.dimension = sprintf('%d',nd);
nrrd.metaData.sizes = sprintf('%d ', [pad,X,Y,Z] );
% ------------------------------------------------------
% Identify the anatmocial axes in the template:
anat = find_anatomical_axes(template.metaData.kinds);
% ------------------------------------------------------
% Make sure the field of view matches that of the template
fov = sscanf(template.metaData.sizes, '%d');
assert( isequal([X,Y,Z],fov(anat)'), ...
    'The size of the input volume doesn''t match the FoV of the template' );
% ------------------------------------------------------
% Kinds:
nrrd.metaData.kinds = 'domain domain domain';
if(nd==4)
    if( size(vol,1)==3 )
        nrrd.metaData.kinds = sprintf('vector %s',nrrd.metaData.kinds);
    elseif( size(vol,1)==6 )
        nrrd.metaData.kinds = sprintf('3D-symmetric-matrix %s',nrrd.metaData.kinds);
    else
        nrrd.metaData.kinds = sprintf('list %s',nrrd.metaData.kinds);
    end
elseif(nd>4)
    for d=1:length(pad)
        nrrd.metaData.kinds = sprintf('list %s',nrrd.metaData.kinds);
    end
end
% ------------------------------------------------------
% Space directions:
axes_directions = template.ijkToLpsTransform(1:3,1:3);
nrrd.metaData.space_directions = sprintf('(%f,%f,%f) (%f,%f,%f) (%f,%f,%f)',reshape(axes_directions,1,9));
for d=1:length(pad)
    nrrd.metaData.space_directions = sprintf('none %s',nrrd.metaData.space_directions);
end
% ------------------------------------------------------
% If the input is a DWI but the output is not, remove
% DWI-related fields:
if(   ( isfield(template.metaData,'modality') && strcmp(template.metaData.modality,'DWMRI') ) || isfield(template.metaData,'DWMRI_b_value')   )
    % Make sure the output is not a DWI:
    nDWI = fov(~anat);
    nDWI = nDWI(1);
    if( (nd~=4) || (pad(1)~=nDWI) )
        nrrd.metaData = remove_DWI_metaData(nrrd.metaData);
        nrrd.metaDataFieldNames = remove_DWI_metaData(nrrd.metaDataFieldNames);
    end
end
% ------------------------------------------------------
end

% -------------------------------------------------------------------------
function metaType = getMetaType(matlabType)
% Determine the metadata type from the Matlab type
switch (matlabType)
    case {'int8'}
        metaType = 'int8';
    case {'uint8'}
        metaType = 'uint8';
    case {'int16'}
        metaType = 'int16';
    case {'uint16'}
        metaType = 'uint16';
    case {'int32'}
        metaType = 'int32';
    case {'uint32'}
        metaType = 'uint32';
    case {'int64'}
        metaType = 'int64';
    case {'uint64'}
        metaType = 'uint64';
    case {'single'}
        metaType = 'float';
    case {'double'}
        metaType = 'double';
    otherwise
        assert(false, 'Unsupported Matlab data type')
end
end

% -------------------------------------------------------------------------
function pos = find_anatomical_axes(str)
strs  = strsplit(str);
mtchs = strfind(strs,'domain');
if( isempty([mtchs{:}]) )
    mtchs = strfind(strs,'space');
    if( isempty([mtchs{:}]) )
        error('Misformed kinds string: %s',str);
    end
end
pos = false( 1, length(mtchs) );
for d=1:length(mtchs)
    pos(d) = ~isempty(mtchs{d});
end
if(sum(pos)~=3)
    error('Misformed kinds string: %s',str);
end
end

% -------------------------------------------------------------------------
function out = remove_DWI_metaData(in)
out    = in;
fnames = fieldnames(in);
for n=1:length(fnames)
    idx = strfind(fnames{n},'DWMRI');
    if(isempty(idx))
        idx = strfind(fnames{n},'modality');
    end
    if(isempty(idx))
        idx = strfind(fnames{n},'measurement_frame');
    end
    if(~isempty(idx))
        out = rmfield(out,fnames{n});
    end
end
end

