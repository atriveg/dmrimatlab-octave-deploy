function niiWrite(nii, filename)

if ~exist('nii','var') || isempty(nii) || ~isfield(nii,'hdr') || ...
        ~isfield(nii,'img') || ~exist('filename','var') || isempty(filename)
    error('Usage: niiWrite(nii, filename)');
end


if isfield(nii.hdr.hist,'magic') && strcmp(nii.hdr.hist.magic(1:3),'ni1')
    filetype = 1;
elseif isfield(nii.hdr.hist,'magic') && strcmp(nii.hdr.hist.magic(1:3),'n+1')
    filetype = 2;
else
    filetype = 0;
end

%  Check file extension. If .gz, unpack it into temp folder
gzipfile = false;
if length(filename) > 2 && strcmp(filename(end-2:end), '.gz')
    gzipfile = true;
    filename = filename(1:end-3);
end

[p,f,e] = fileparts(filename);

switch(filetype)
    case {0,1}
        if( ~strcmp(e,'.hdr') && ~strcmp(e,'.img') )
            warning('You selected extension %s but this structure type will be saved as a hdr/img',e);
        end
    case 2
        if( ~strcmp(e,'.nii') )
            warning('You selected extension %s but this structure type will be saved as a nii',e);
        end
end

fileprefix = fullfile(p, f);

write_nii( nii, filetype, fileprefix, gzipfile );

end


%-----------------------------------------------------------------------------------
function write_nii(nii, filetype, fileprefix, gzipfile )

hdr = nii.hdr;

if isfield(nii,'ext') && ~isempty(nii.ext)
    ext = nii.ext;
    [ext, esize_total] = verify_nii_ext(ext);
else
    ext = [];
end

switch double(hdr.dime.datatype)
    case   1
        hdr.dime.bitpix = int16(1 ); precision = 'ubit1';
    case   2
        hdr.dime.bitpix = int16(8 ); precision = 'uint8';
    case   4
        hdr.dime.bitpix = int16(16); precision = 'int16';
    case   8
        hdr.dime.bitpix = int16(32); precision = 'int32';
    case  16
        hdr.dime.bitpix = int16(32); precision = 'float32';
    case  32
        hdr.dime.bitpix = int16(64); precision = 'float32';
    case  64
        hdr.dime.bitpix = int16(64); precision = 'float64';
    case 128
        hdr.dime.bitpix = int16(24); precision = 'uint8';
    case 256
        hdr.dime.bitpix = int16(8 ); precision = 'int8';
    case 512
        hdr.dime.bitpix = int16(16); precision = 'uint16';
    case 768
        hdr.dime.bitpix = int16(32); precision = 'uint32';
    case 1024
        hdr.dime.bitpix = int16(64); precision = 'int64';
    case 1280
        hdr.dime.bitpix = int16(64); precision = 'uint64';
    case 1792
        hdr.dime.bitpix = int16(128); precision = 'float64';
    otherwise
        error('This datatype is not supported');
end

if(gzipfile)
    gext = '.gz';
    mode = 'wbz';
else
    gext = '';
    mode = 'wb';
end

if filetype == 2
    filename = sprintf('%s.nii%s',fileprefix,gext);
    fid      = fopen( filename, mode );
    assert( fid>=0, sprintf('Cannot open %s for writing',filename) );

    hdr.dime.vox_offset = 352;

    if ~isempty(ext)
        hdr.dime.vox_offset = hdr.dime.vox_offset + esize_total;
    end

    hdr.hist.magic = 'n+1';
    writeNiiHdr(hdr, fid);

    if ~isempty(ext)
        save_nii_ext(ext, fid);
    end
elseif filetype == 1
    filename = sprintf('%s.hdr%s',fileprefix,gext);
    fid      = fopen( filename, mode );
    assert( fid>=0, sprintf('Cannot open %s for writing',filename) );

    hdr.dime.vox_offset = 0;
    hdr.hist.magic = 'ni1';
    writeNiiHdr(hdr, fid);

    if ~isempty(ext)
        save_nii_ext(ext, fid);
    end

    fclose(fid);
    filename = sprintf('%s.img%s',fileprefix,gext);
    fid      = fopen( filename, mode );
    assert( fid>=0, sprintf('Cannot open %s for writing',filename) );
else
    filename = sprintf('%s.hdr%s',fileprefix,gext);
    fid      = fopen( filename, mode );
    assert( fid>=0, sprintf('Cannot open %s for writing',filename) );

    writeNiiHdrAnalyze(hdr, fid);

    fclose(fid);
    filename = sprintf('%s.img%s',fileprefix,gext);
    fid      = fopen( filename, mode );
    assert( fid>=0, sprintf('Cannot open %s for writing',filename) );
end

if filetype == 2 && isempty(ext)
    skip_bytes = double(hdr.dime.vox_offset) - 348;
else
    skip_bytes = 0;
end

if double(hdr.dime.datatype) == 128

    %  RGB planes are expected to be in the 4th dimension of nii.img
    %
    if(size(nii.img,4)~=3)
        error('The NII structure does not appear to have 3 RGB color planes in the 4th dimension');
    end

    nii.img = permute(nii.img, [4 1 2 3 5 6 7 8]);
end

%  For complex float32 or complex float64, voxel values
%  include [real, imag]
%
if hdr.dime.datatype == 32 || hdr.dime.datatype == 1792
    real_img = real(nii.img(:))';
    nii.img = imag(nii.img(:))';
    nii.img = [real_img; nii.img];
end

if skip_bytes
    fwrite(fid, zeros(1,skip_bytes), 'uint8');
end

fwrite(fid, nii.img, precision);
fclose(fid);

end

function [ext, esize_total] = verify_nii_ext(ext)

if ~isfield(ext, 'section')
    error('Incorrect NIFTI header extension structure.');
elseif ~isfield(ext, 'num_ext')
    ext.num_ext = length(ext.section);
elseif ~isfield(ext, 'extension')
    ext.extension = [1 0 0 0];
end

esize_total = 0;

for i=1:ext.num_ext
    if ~isfield(ext.section(i), 'ecode') || ~isfield(ext.section(i), 'edata')
        error('Incorrect NIFTI header extension structure.');
    end

    ext.section(i).esize = ceil((length(ext.section(i).edata)+8)/16)*16;
    ext.section(i).edata = [ext.section(i).edata ...
        zeros(1,ext.section(i).esize-length(ext.section(i).edata)-8)];
    esize_total = esize_total + ext.section(i).esize;
end

end

function save_nii_ext(ext, fid)

if ~isfield(ext,'extension') || ~isfield(ext,'section') || ~isfield(ext,'num_ext')
    error('Wrong header extension');
end

write_ext(ext, fid);

end


function write_ext(ext, fid)

fwrite(fid, ext.extension, 'uchar');

for i=1:ext.num_ext
    fwrite(fid, ext.section(i).esize, 'int32');
    fwrite(fid, ext.section(i).ecode, 'int32');
    fwrite(fid, ext.section(i).edata, 'uchar');
end

end
