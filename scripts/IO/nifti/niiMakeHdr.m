function nii = niiMakeHdr( volume, T, datatype, description )

if( nargin<1 )
    volume = single([]);
end

if( (nargin<2) || isempty(T) )
    T = eye(4);
end

if( (nargin<3) || isempty(datatype) )
    datatype = class(volume);
else
    volume   = cast(volume,datatype);
end
ndt = num_data_type( datatype, ~isreal(volume) );

if( (nargin<4) || isempty(description) )
    description = 'niiMakeHdr-generated header';
end

% ---------------------------------------
nii.img = volume;
% ---------------------------------------
dims = size(nii.img);
dims = [length(dims) dims ones(1,8)];
dims = dims(1:8);
if( (ndt==128) || (ndt==511) )
    dims(5) = [];
    dims(1) = dims(1) - 1;
    dims = [dims 1];
end
if( ndims(nii.img) > 7 )
    error('NIfTI only allows a maximum of 7 Dimension matrix');
end
% ---------------------------------------

maxval = double(max(nii.img(:)));
minval = double(min(nii.img(:)));

nii.hdr = make_header(dims, T, ndt, description, maxval, minval);

end


%---------------------------------------------------------------------
function hdr = make_header(dims, T, ndt, description, maxval, minval)
hdr.hk   = header_key;
hdr.dime = image_dimension(dims, T, ndt, maxval, minval);
hdr.hist = data_history( T, description );
end


%---------------------------------------------------------------------
function hk = header_key

hk.sizeof_hdr       = 348; % must be 348!
hk.data_type        = '';
hk.db_name          = '';
hk.extents          = 0;
hk.session_error    = 0;
hk.regular          = 'r';
hk.dim_info         = 0;

end

%---------------------------------------------------------------------
function dime = image_dimension(dims, T, ndt, maxval, minval)

dime.dim         = dims;
dime.intent_p1   = 0;
dime.intent_p2   = 0;
dime.intent_p3   = 0;
dime.intent_code = 0;
dime.datatype    = ndt;

switch(ndt)
    case {2,256}
        dime.bitpix = 8;
    case {4,512}
        dime.bitpix = 16;
    case 128
        dime.bitpix = 24;
    case {8,16,768}
        dime.bitpix = 32;
    case {32,64}
        dime.bitpix = 64;
    case 511
        dime.bitpix = 96;
    case 1792
        dime.bitpix = 128;
    otherwise
        error('Datatype is not supported by niiMakeHdr');
end

dime.slice_start = 0;

spacing = [ 0, sqrt(sum(T(1:3,1:3).*T(1:3,1:3),1)), zeros(1,7) ];
spacing = spacing(1:8);
dime.pixdim = spacing;

dime.vox_offset = 0;
dime.scl_slope = 0;
dime.scl_inter = 0;
dime.slice_end = 0;
dime.slice_code = 0;
dime.xyzt_units = 0;
dime.cal_max = 0;
dime.cal_min = 0;
dime.slice_duration = 0;
dime.toffset = 0;
dime.glmax = maxval;
dime.glmin = minval;

end


%---------------------------------------------------------------------
function hist = data_history( T, description )
q = rotmatrix2quaternion(T);
% --
if(~isempty(q))
    hist.qform_code = 1;
else
    hist.qform_code = 0; % Don't use quaternion representation
end
hist.sform_code = 1;
% --
hist.descrip = description;
hist.aux_file = 'none';
if(~isempty(q))
    hist.quatern_b = q(2);
    hist.quatern_c = q(3);
    hist.quatern_d = q(4);
else
    hist.quatern_b = 0;
    hist.quatern_c = 0;
    hist.quatern_d = 0;
end
hist.qoffset_x = T(1,4);
hist.qoffset_y = T(2,4);
hist.qoffset_z = T(3,4);
hist.srow_x = T(1,:);
hist.srow_y = T(2,:);
hist.srow_z = T(3,:);
hist.intent_name = '';
hist.magic = 'n+1';
hist.originator = T(1:3,4)';
end

%---------------------------------------------------------------------
function ndt = num_data_type(datatype,cplxflag)
switch datatype
    case 'uint8'
        ndt = 2;
    case 'int16'
        ndt = 4;
    case 'int32'
        ndt = 8;
    case 'single'
        if(cplxflag)
            ndt = 32;
        else
            ndt = 16;
        end
    case 'double'
        if(cplxflag)
            ndt = 1792;
        else
            ndt = 64;
        end
    case 'int8'
        ndt = 256;
    case 'uint16'
        ndt = 512;
    case 'uint32'
        ndt = 768;
    otherwise
        error('Datatype %s is not supported by niiMakeHdr',datatype);
end
end

% -------------------------------------------------------------------------
function q = rotmatrix2quaternion(T)
q = [];
% --------------------------------------------
% Keep just the rotation part of T:
T = T(1:3,1:3);
% Normalize each column:
n = sqrt(sum(T.*T,1));
T = T./n;
% --------------------------------------------
% In case the determinant is negative, this
% is not a rotation matrix (one of the axis is
% swaped), so a quaternion cannot represent it.
% Just return an empty vector and handle it
% outside:
if(det(T)<0), return; end
% --------------------------------------------
% To ensure we start with a rotation matrix,
% let's use Cayley's transform:
I3 = eye(3);
% This should be skew-symmetric...
A  = (I3-T)*((I3+T)\I3);
% ... force it to actually be:
A  = (A-A')/2;
% Map back to a rotation matrix:
T  = (I3-A)*((I3+A)\I3);
% Sanity check:
if( any(isinf(T(:))) || any(isnan(T(:))) ), return; end
% --------------------------------------------
m00 = T(1,1); m01 = T(1,2); m02 = T(1,3);
m10 = T(2,1); m11 = T(2,2); m12 = T(2,3);
m20 = T(3,1); m21 = T(3,2); m22 = T(3,3);
% --------------------------------------------
if( m22 < 0 )
    if ( m00 > m11 )
        t = 1 + m00 - m11 - m22;
        q = [ m21-m12, t, m01+m10, m20+m02 ];
    else
        t = 1 - m00 + m11 - m22;
        q = [ m02-m20, m01+m10, t, m12+m21  ];
    end
else
    if( m00 < -m11 )
        t = 1 - m00 - m11 + m22;
        q = [ m10-m01, m20+m02, m12+m21, t ];
    else
        t = 1 + m00 + m11 + m22;
        q = [ -t, m12-m21, m20-m02, m01-m10 ];
    end
end
% --------------------------------------------
q = q/norm(q);
if(q(1)<0)
    q = -q;
end
% --------------------------------------------
end

