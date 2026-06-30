function [img,hdr] = readNiiImg(hdr,filetype,fileprefix,machine,gzipfile)

if nargin<4
    error('Usage: [img,hdr] = load_nii_img(hdr,filetype,fileprefix,machine,[img_idx],[dim5_idx],[dim6_idx],[dim7_idx],[old_RGB],[slice_idx]);');
end

[img,hdr] = read_image(hdr,filetype,fileprefix,machine,gzipfile);

end


%---------------------------------------------------------------------
function [img,hdr] = read_image(hdr,filetype,fileprefix,machine,gzipfile)

switch filetype
    case {0, 1}
        filename = [fileprefix '.img'];
    case 2
        filename = [fileprefix '.nii'];
end
if(gzipfile)
    filename = sprintf('%s.gz',filename);
    mode = 'rbz';
else
    mode = 'rb';
end

fid = fopen( filename , mode, machine );
assert( fid>=0, sprintf('Cannot open file %s for reading',filename) );

%  Set bitpix according to datatype
%
%  /*Acceptable values for datatype are*/
%
%     0 None                     (Unknown bit per voxel) % DT_NONE, DT_UNKNOWN
%     1 Binary                         (ubit1, bitpix=1) % DT_BINARY
%     2 Unsigned char         (uchar or uint8, bitpix=8) % DT_UINT8, NIFTI_TYPE_UINT8
%     4 Signed short                  (int16, bitpix=16) % DT_INT16, NIFTI_TYPE_INT16
%     8 Signed integer                (int32, bitpix=32) % DT_INT32, NIFTI_TYPE_INT32
%    16 Floating point    (single or float32, bitpix=32) % DT_FLOAT32, NIFTI_TYPE_FLOAT32
%    32 Complex, 2 float32      (Use float32, bitpix=64) % DT_COMPLEX64, NIFTI_TYPE_COMPLEX64
%    64 Double precision  (double or float64, bitpix=64) % DT_FLOAT64, NIFTI_TYPE_FLOAT64
%   128 uint8 RGB                 (Use uint8, bitpix=24) % DT_RGB24, NIFTI_TYPE_RGB24
%   256 Signed char            (schar or int8, bitpix=8) % DT_INT8, NIFTI_TYPE_INT8
%   511 Single RGB              (Use float32, bitpix=96) % DT_RGB96, NIFTI_TYPE_RGB96
%   512 Unsigned short               (uint16, bitpix=16) % DT_UNINT16, NIFTI_TYPE_UNINT16
%   768 Unsigned integer             (uint32, bitpix=32) % DT_UNINT32, NIFTI_TYPE_UNINT32
%  1024 Signed long long              (int64, bitpix=64) % DT_INT64, NIFTI_TYPE_INT64
%  1280 Unsigned long long           (uint64, bitpix=64) % DT_UINT64, NIFTI_TYPE_UINT64
%  1536 Long double, float128  (Unsupported, bitpix=128) % DT_FLOAT128, NIFTI_TYPE_FLOAT128
%  1792 Complex128, 2 float64  (Use float64, bitpix=128) % DT_COMPLEX128, NIFTI_TYPE_COMPLEX128
%  2048 Complex256, 2 float128 (Unsupported, bitpix=256) % DT_COMPLEX128, NIFTI_TYPE_COMPLEX128
%
switch hdr.dime.datatype
    case   1
        hdr.dime.bitpix = 1;  precision = 'ubit1';
    case   2
        hdr.dime.bitpix = 8;  precision = 'uint8';
    case   4
        hdr.dime.bitpix = 16; precision = 'int16';
    case   8
        hdr.dime.bitpix = 32; precision = 'int32';
    case  16
        hdr.dime.bitpix = 32; precision = 'float32';
    case  32
        hdr.dime.bitpix = 64; precision = 'float32';
    case  64
        hdr.dime.bitpix = 64; precision = 'float64';
    case 128
        hdr.dime.bitpix = 24; precision = 'uint8';
    case 256
        hdr.dime.bitpix = 8;  precision = 'int8';
    case 511
        hdr.dime.bitpix = 96; precision = 'float32';
    case 512
        hdr.dime.bitpix = 16; precision = 'uint16';
    case 768
        hdr.dime.bitpix = 32; precision = 'uint32';
    case 1024
        hdr.dime.bitpix = 64; precision = 'int64';
    case 1280
        hdr.dime.bitpix = 64; precision = 'uint64';
    case 1792
        hdr.dime.bitpix = 128; precision = 'float64';
    otherwise
        error('This datatype is not supported');
end

tmp = hdr.dime.dim(2:end);
tmp(tmp < 1) = 1;
hdr.dime.dim(2:end) = tmp;

%  move pointer to the start of image block
%
switch filetype
    case {0, 1}
        fread(fid, 0, 'uint8=>uint8');
    case 2
        % Cannot use fseek with gzipped files!!
        fread(fid, hdr.dime.vox_offset, 'uint8=>uint8');
end

%  Load whole image block for old Analyze format or binary image;
%  otherwise, load images that are specified in img_idx, dim5_idx,
%  dim6_idx, and dim7_idx
%
%  For binary image, we have to read all because pos can not be
%  seeked in bit and can not be calculated the way below.
%

%  For each frame, precision of value will be read
%  in img_siz times, where img_siz is only the
%  dimension size of an image, not the byte storage
%  size of an image.
%
img_siz = prod(hdr.dime.dim(2:8));

%  For complex float32 or complex float64, voxel values
%  include [real, imag]
%
if hdr.dime.datatype == 32 || hdr.dime.datatype == 1792
    img_siz = img_siz * 2;
end

%MPH: For RGB24, voxel values include 3 separate color planes
%
if hdr.dime.datatype == 128 || hdr.dime.datatype == 511
    img_siz = img_siz * 3;
end

img = fread(fid, img_siz, sprintf('*%s',precision));
fclose(fid);

d3 = hdr.dime.dim(4);
d4 = hdr.dime.dim(5);
d5 = hdr.dime.dim(6);
d6 = hdr.dime.dim(7);
d7 = hdr.dime.dim(8);

slice_idx = 1:d3;
img_idx = 1:d4;
dim5_idx = 1:d5;
dim6_idx = 1:d6;
dim7_idx = 1:d7;

%  For complex float32 or complex float64, voxel values
%  include [real, imag]
%
if hdr.dime.datatype == 32 || hdr.dime.datatype == 1792
    img = reshape(img, [2, length(img)/2]);
    img = complex(img(1,:)', img(2,:)');
end



%  Update the global min and max values
%
hdr.dime.glmax = double(max(img(:)));
hdr.dime.glmin = double(min(img(:)));

%  old_RGB treat RGB slice by slice, now it is treated voxel by voxel
%
if hdr.dime.datatype == 128 && hdr.dime.bitpix == 24
    % remove squeeze
    img = (reshape(img, [3 hdr.dime.dim(2:3) length(slice_idx) length(img_idx) length(dim5_idx) length(dim6_idx) length(dim7_idx)]));
    img = permute(img, [2 3 4 1 5 6 7 8]);
elseif hdr.dime.datatype == 511 && hdr.dime.bitpix == 96
    img = double(img(:));
    img = single((img - min(img))/(max(img) - min(img)));
    % remove squeeze
    img = (reshape(img, [3 hdr.dime.dim(2:3) length(slice_idx) length(img_idx) length(dim5_idx) length(dim6_idx) length(dim7_idx)]));
    img = permute(img, [2 3 4 1 5 6 7 8]);
else
    % remove squeeze
    img = (reshape(img, [hdr.dime.dim(2:3) length(slice_idx) length(img_idx) length(dim5_idx) length(dim6_idx) length(dim7_idx)]));
end

hdr.dime.dim(4) = length(slice_idx);
hdr.dime.dim(5) = length(img_idx);
hdr.dime.dim(6) = length(dim5_idx);
hdr.dime.dim(7) = length(dim6_idx);
hdr.dime.dim(8) = length(dim7_idx);

end

