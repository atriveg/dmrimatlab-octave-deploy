function nrrdSave( img, filename )
% Write image and metadata to a NRRD file (see http://teem.sourceforge.net/nrrd/format.html)
%   img.pixelData: pixel data array
%   img.ijkToLpsTransform: pixel (IJK) to physical (LPS, assuming 'space' is 'left-posterior-superior')
%     coordinate system transformation, the origin of the IJK coordinate system is (1,1,1) to match Matlab matrix indexing
%   img.metaData: Contains all the descriptive information in the image header. The following fields are ignored:
%     sizes: computed to match size of img.pixelData
%     type: computed to match type of img.pixelData
%     kinds: computed to match dimension of img.pixelData
%     dimension: computed to match dimension of img.pixelData
%     space_directions: ignored if img.ijkToLpsTransform is defined
%     space_origin: ignored if img.ijkToLpsTransform is defined
%   img.metaData: Contains the list of full NRRD field names for each
%     metaData field name. All fields should be listed here that have a
%     special character in their name (such as dot or space).
%   img.metaDataFieldNames: Contains full names of metadata fields that cannot be used as Matlab field names because they contains
%     special characters (space, dot, etc). Full field names are used for determining the field name to be used in the NRRD file
%     from the Matlab metadata field name.
%
% Supports writing of 3D and 4D volumes.
%
% Examples:
%
% 1. Using output from nrrdread:
%
%   img = nrrdread('testData\MRHeadRot.nrrd')
%   nrrdwrite('testOutput.nrrd', img)
%
% 2. Creating volume from scratch - minimal example
%
%   [x,y,z] = meshgrid([-10:10],[-12:15],[-8:6]);
%   img.pixelData = x/3+y/4+z/2;
%
%   nrrdwrite('testOutput.nrrd', img);
%
% 3. Creating volume from scratch
%
%   % Set pixel data
%   [x,y,z] = meshgrid([-10:10],[-12:15],[-8:6]);
%   img.pixelData = x/3+y/4+z/2;
%
%   % Define origin, spacing, axis directions by a homogeneous transformation matrix:
%   img.ijkToLpsTransform = [ 1.2 0 0 10; 0 1.2 0 12; 0 0 3.0 -22; 0 0 0 1];
%
%   % Enable compression
%   img.metaData.encoding='gzip';
%
%   nrrdwrite('testOutput.nrrd', img);
%

% Open file for writing
fid = fopen(filename, 'w');
assert( fid>=0, sprintf('Cannot open %s for writting',filename) );
cleaner = onCleanup( @() safe_fclose(fid) );

standardFieldNames = { 'type', 'dimension', 'space', 'sizes', 'space directions', 'kinds', 'endian', 'encoding', 'space origin', 'measurement frame', 'data file' };

fprintf(fid,'NRRD0005\n');
fprintf(fid,'# Complete NRRD file format specification at:\n');
fprintf(fid,'# http://teem.sourceforge.net/nrrd/format.html\n');

% Create/override mandatory fields

img.metaData.type = getMetaType(class(img.pixelData));
img.metaData.dimension = sprintf( '%d', max(length(size(img.pixelData)),3) ); % ndims is not defined for int16 arrays
if ~isfield(img.metaData,'space')
    img.metaData.space = 'right-anterior-superior';
else
    img.metaData.space = expand_space_string(img.metaData.space);
end
img.metaData.sizes=num2str(size(img.pixelData));

if isfield(img,'ijkToLpsTransform')
    % NOTE: Always use 0-based indexing:
    axes_origin = img.ijkToLpsTransform(1:3,4);
    img.metaData.space_origin = sprintf('(%f,%f,%f)',reshape(axes_origin,1,3));
    axes_directions = img.ijkToLpsTransform(1:3,1:3);
    switch (img.metaData.dimension)
        case '3'
            img.metaData.space_directions = sprintf('(%f,%f,%f) (%f,%f,%f) (%f,%f,%f)',reshape(axes_directions,1,9));
        case '4'
            img.metaData.space_directions = sprintf('none (%f,%f,%f) (%f,%f,%f) (%f,%f,%f)',reshape(axes_directions,1,9));
        case '5'
            img.metaData.space_directions = sprintf('none none (%f,%f,%f) (%f,%f,%f) (%f,%f,%f)',reshape(axes_directions,1,9));
        otherwise
            assert(false, 'Unsupported pixel data dimension')
    end
end

if( ~isfield(img.metaData,'space_directions') )
    switch (img.metaData.dimension)
        case '3'
            img.metaData.space_directions = '(1,0,0) (0,1,0) (0,0,1)';
        case '4'
            img.metaData.space_directions = 'none (1,0,0) (0,1,0) (0,0,1)';
        case '5'
            img.metaData.space_directions = 'none none (1,0,0) (0,1,0) (0,0,1)';
        otherwise
            assert(false, 'Unsupported pixel data dimension')
    end
end

switch (img.metaData.dimension)
    case '3'
        img.metaData.kinds='domain domain domain';
    case '4'
        if(~isfield(img.metaData,'kinds'))
            img.metaData.kinds='list domain domain domain';
        end
    case '5'
        if(~isfield(img.metaData,'kinds'))
            img.metaData.kinds='list list domain domain domain';
        end
    otherwise
        assert(false, 'Unsupported pixel data dimension')
end

if ~isfield(img.metaData,'endian')
    img.metaData.endian='little';
end

if ~isfield(img.metaData,'encoding')
    img.metaData.encoding='raw';
end

% Make sure that standard field names that contain special
% characters have their full field names defined.
for k=1:length(standardFieldNames)
    fullFieldName=standardFieldNames{k};
    fieldName=regexprep(fullFieldName,'\W','_');
    if ~strcmp(fieldName,fullFieldName)
        img.metaDataFieldNames.(fieldName)=fullFieldName;
    end
end

% --------------------------------------------
[folder,name,ext] = fileparts(filename);
switch(ext)
    case '.nhdr'
        NHDR = true;
        switch(img.metaData.encoding)
            case {'raw'}
                addext = '';
            case {'gzip', 'gz'}
                addext = '.gz';
            otherwise
                error('Unsupported encoding for writting: %s',img.metaData.encoding);
        end
        datafile     = fullfile( folder, sprintf('%s.raw%s',name,addext) );
        datafilename = sprintf('%s.raw%s',name,addext);
        img.metaData.data_file = datafilename;
        img.metaDataFieldNames.data_file = 'data file';
    case '.nrrd'
        NHDR = false;
        if( isfield(img.metaData,'data_file') )
            img.metaData = rmfield(img.metaData,'data_file');
        end
        if( isfield(img.metaDataFieldNames,'data_file') )
            img.metaDataFieldNames = rmfield(img.metaDataFieldNames,'data_file');
        end
    otherwise
        error('The only extensions allowed for the output file are .nhdr or .nrrd, got <%s>',ext);
end
% --------------------------------------------

% Print the header data to the output file
metaDataCellArr = struct2cell(img.metaData);
fields = fieldnames(img.metaData);
for i=1:numel(fields)
    writeFieldName(fid, fields{i}, img.metaDataFieldNames, standardFieldNames);
    writeDataByType(fid,metaDataCellArr{i});
end
fprintf(fid,'\n');

% Write pixel data
if(NHDR) % Dettached header
    fclose(fid);
    switch(img.metaData.encoding)
        case {'raw'}
            fid = fopen(datafile,'wb');
        case {'gzip', 'gz'}
            fid = fopen(datafile,'wbz');
        otherwise
            error('Unsupported encoding for writting: %s',img.metaData.encoding);
    end
    assert( fid>0, sprintf('Cannot open data file %s for writting',datafile) );
    fwrite( fid, img.pixelData, class(img.pixelData) );
    fclose(fid);
else % Attached header
    switch(img.metaData.encoding)
        case {'raw'}
            fwrite( fid, img.pixelData, class(img.pixelData) );
            fclose(fid);
        case {'gzip', 'gz'}
            fclose(fid);
            cmd = sprintf('gzip -c >> "%s"', filename);
            pipe = popen(cmd, 'w');
            assert( pipe>=0, 'Cannot open pipe to gzip the data to the output file' );
            fwrite( pipe, img.pixelData, class(img.pixelData) );
            pclose(pipe);
        otherwise
            error('Unsupported encoding: %s',img.metaData.encoding);
    end
end

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function writeFieldName(fid, fieldName, fullFieldNames, standardFieldNames)
% If full field name is listed in img.metaDataFieldNames then use that
% instead of the Matlab field name.
if isfield(fullFieldNames,fieldName)
    fullFieldName = fullFieldNames.(fieldName);
else
    fullFieldName = fieldName;
end
isStandardFieldName = ~isempty(find(strcmp(fullFieldName, standardFieldNames), 1));
if isStandardFieldName
    % Standard field names are separated by :
    fprintf(fid,'%s: ',fullFieldName);
else
    % Custom field names are separated by :=
    fprintf(fid,'%s:=',fullFieldName);
end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function writeDataByType(fid, data)
% Function that writes the header data to file based on the type of data
% params: - fid of file to write to
%         - data from header to write
if ischar(data)
    fprintf(fid,'%s\n',data);
else
    fprintf(fid,'%d ',data);
    fprintf(fid,'\n');
end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
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

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function space = expand_space_string(space)
space = lower(space);
if(length(space)==3)
    idx = (space=='rai') + 1;
    s1  = {'left-','right-'};
    s2  = {'posterior-','anterior-'};
    s3  = {'superior','inferior'};
    space = sprintf('%s%s%s', s1{idx(1)}, s2{idx(2)}, s3{idx(3)} );
end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function safe_fclose(fid)
if(is_valid_file_id(fid))
    fclose(fid);
end
end
