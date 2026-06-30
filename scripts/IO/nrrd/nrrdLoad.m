function img = nrrdLoad(filename)
% Read image and metadata from a NRRD file (see http://teem.sourceforge.net/nrrd/format.html)
%   img = cli_imageread(filename) reads the image volume and associated metadata
%
%   img.pixelData: pixel data array
%   img.ijkToLpsTransform: pixel (IJK) to physical (LPS, assuming 'space' is 'left-posterior-superior')
%     coordinate system transformation, the origin of the IJK coordinate system is (1,1,1) to match Matlab matrix indexing
%   img.metaData: contains all the descriptive information in the image header
%   img.metaDataFieldNames: Contains full names of metadata fields that cannot be used as Matlab field names because they contains
%     special characters (space, dot, etc). Special characters in field names are replaced by underscore by default when the NRRD
%     file is read. Full field names are used when writing the image to NRRD file.
%
%  Supports reading of 3D and 4D volumes.
%
%   Current limitations/caveats:
%   * Block datatype is not supported.
%   * Only tested with "gzip" and "raw" file encodings.
%
% Partly based on the nrrdread.m function with copyright 2012 The MathWorks, Inc.

fid = fopen(filename, 'rb');
assert( fid > 0, sprintf('Could not open %s for reading',filename) ) ;
cleaner = onCleanup( @() safe_fclose(fid) );

% NRRD files must start with the NRRD word and a version number
theLine = fgetl(fid);
assert(numel(theLine) >= 4, 'Bad signature in file.')
assert(isequal(theLine(1:4), 'NRRD'), 'Bad signature in file.')

% The general format of a NRRD file (with attached header) is:
%
%     NRRD000X
%     <field>: <desc>
%     <field>: <desc>
%     # <comment>
%     ...
%     <field>: <desc>
%     <key>:=<value>
%     <key>:=<value>
%     <key>:=<value>
%     # <comment>
%
%     <data><data><data><data><data><data>...

img.metaData = {};
img.metaDataFieldNames = {};
% Parse the file a line at a time.
data_offset = 0; %#ok<NASGU>
while (true)

    theLine = fgetl(fid);

    if (isempty(theLine) || feof(fid))
        % End of the header.
        data_offset = ftell(fid);
        fclose(fid);
        break;
    end

    if (isequal(theLine(1), '#'))
        % Comment line.
        continue;
    end

    % "fieldname:= value" or "fieldname: value" or "fieldname:value"
    parsedLine = regexp(theLine, ':=?\s*', 'split','once');

    assert(numel(parsedLine) == 2, 'Parsing error')

    field = parsedLine{1};
    value = parsedLine{2};

    % Cannot use special characters in field names, so replace them by underscore
    % and store the original field name in img.metaDataFieldNames so that it can be
    % restored when writing the data.
    fieldName=regexprep(field,'\W','_');
    if ~strcmp(fieldName,field)
        img.metaDataFieldNames.(fieldName) = field;
    end

    % In case a tag is duplicated, keep just the first one. This is necessary
    % in DWI volumes since the "space" appears both as space: blabla and as
    % space:=blabla. The second one occurs after the gradient table and it is
    % not correct!
    if(isempty(img.metaData))
        img.metaData(1).(fieldName) = value;
    else
        if(~isfield(img.metaData(1),fieldName))
            img.metaData(1).(fieldName) = value;
        end
    end

end

datatype = getDatatype(img.metaData.type);

% Get the size of the data.
assert(isfield(img.metaData, 'sizes') && ...
    isfield(img.metaData, 'dimension') && ...
    isfield(img.metaData, 'encoding'), ...
    'Missing required metadata fields (sizes, dimension, or encoding).')

dims = sscanf(img.metaData.sizes, '%d');
ndims = sscanf(img.metaData.dimension, '%d');
assert(numel(dims) == ndims);

if(isfield(img.metaData,'data_file'))
    % Dettached header
    data_offset = 0;
    [pathstr,~,~]  = fileparts(filename);
    if(~isempty(pathstr))
        data_file_name = [pathstr,filesep,img.metaData.data_file];
    else
        data_file_name = img.metaData.data_file;
    end
else
    data_file_name = filename;
end

switch (img.metaData.encoding)
    case {'raw'}
        fid = fopen( data_file_name, 'rb' );
        assert( fid>=0, sprintf('Cannot open data file %s for reading',data_file_name) );
        fseek( fid, data_offset, 'bof' );
        data = fread( fid, inf, [datatype '=>' datatype]);
        fclose(fid);
    case {'gzip', 'gz'}
        if(data_offset<1)
            % Dettached header
            fid = fopen( data_file_name, 'rbz' );
            assert( fid>=0, sprintf('Cannot open data file %s for reading',data_file_name) );
            data = fread( fid, inf, [datatype '=>' datatype]);
            fclose(fid);
        else
            % Attached header. Use Octave's pipes:
            cmd = sprintf('tail -c +%d "%s" | gzip -d -c', data_offset + 1, data_file_name );
            pipe = popen(cmd, 'r');
            assert( pipe>=0, sprintf('Cannot open pipe to gunzip data file: %s',data_file_name) );
            data = fread(pipe, inf, [datatype '=>' datatype]);
            pclose(pipe);
        end
    case {'bzip2', 'bz2'}
        cmd = sprintf('tail -c +%d "%s" | bzip2 -d -c', data_offset + 1, data_file_name );
        pipe = popen(cmd, 'r');
        assert( pipe>=0, sprintf('Cannot open pipe to bunzip data file: %s',data_file_name) );
        data = fread(pipe, inf, [datatype '=>' datatype]);
        pclose(pipe);
    case {'txt', 'text', 'ascii'}
        fid = fopen( data_file_name, 'r' );
        assert( fid>=0, sprintf('Cannot open data file %s for reading',data_file_name) );
        data = fscanf(fid, '%f');
        fclose(fid);
        data = cast(data, datatype);
    otherwise
        assert(false, 'Unsupported encoding')
end

if isfield(img.metaData, 'endian')
    data = adjustEndian(data, img.metaData);
end

img.pixelData = reshape(data, dims');

% Read the image directions whatever their order is:
if(ndims>3)
    if( ~isfield(img.metaData, 'kinds') )
        error('Missing ''kinds'' field in the NRRD header');
    end
    strs  = strsplit(img.metaData.kinds);
    if(length(strs)~=ndims)
        error('Misformed kinds string in NRRD file: %s',img.metaData.kinds);
    end
    mtchs = strfind(strs,'domain');
    if( isempty([mtchs{:}]) )
        mtchs = strfind(strs,'space');
        if( isempty([mtchs{:}]) )
            error('Misformed kinds string in NRRD file: %s',img.metaData.kinds);
        end
    end
    pos = false( 1, length(mtchs) );
    for d=1:length(mtchs)
        pos(d) = ~isempty(mtchs{d});
    end
    if(sum(pos)~=3)
        error('Misformed kinds string in NRRD file: %s',img.metaData.kinds);
    end
    readstr       = cell(1,ndims);
    readstr(pos)  = '(%f,%f,%f)';
    readstr(~pos) = 'none';
    readstr       = strjoin(readstr,' ');
else
    readstr = '(%f,%f,%f) (%f,%f,%f) (%f,%f,%f)';
end
axes_directions = reshape(sscanf(img.metaData.space_directions,readstr),3,3);
axes_origin     = sscanf(img.metaData.space_origin,'(%f,%f,%f)');
% NOTE: we will always use zero-based indexing.
img.ijkToLpsTransform = [ [axes_directions, axes_origin]; [0 0 0 1] ];
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function datatype = getDatatype(metaType)
% Determine the datatype
switch (metaType)
    case {'signed char', 'int8', 'int8_t'}
        datatype = 'int8';
    case {'uchar', 'unsigned char', 'uint8', 'uint8_t'}
        datatype = 'uint8';
    case {'short', 'short int', 'signed short', 'signed short int', ...
            'int16', 'int16_t'}
        datatype = 'int16';
    case {'ushort', 'unsigned short', 'unsigned short int', 'uint16', ...
            'uint16_t'}
        datatype = 'uint16';
    case {'int', 'signed int', 'int32', 'int32_t'}
        datatype = 'int32';
    case {'uint', 'unsigned int', 'uint32', 'uint32_t'}
        datatype = 'uint32';
    case {'longlong', 'long long', 'long long int', 'signed long long', ...
            'signed long long int', 'int64', 'int64_t'}
        datatype = 'int64';
    case {'ulonglong', 'unsigned long long', 'unsigned long long int', ...
            'uint64', 'uint64_t'}
        datatype = 'uint64';
    case {'float'}
        datatype = 'single';
    case {'double'}
        datatype = 'double';
    otherwise
        assert(false, 'Unknown datatype')
end
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function data = adjustEndian(data, meta)
[~,~,endian] = computer();
needToSwap = (isequal(endian, 'B') && isequal(lower(meta.endian), 'little')) || ...
    (isequal(endian, 'L') && isequal(lower(meta.endian), 'big'));
if (needToSwap)
    data = swapbytes(data);
end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function safe_fclose(fid)
if(is_valid_file_id(fid))
    fclose(fid);
end
end
