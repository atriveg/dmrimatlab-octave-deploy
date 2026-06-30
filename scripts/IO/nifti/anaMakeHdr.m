function ana = anaMakeHdr( volume, T, datatype, description )

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
ndt = num_data_type( datatype );

if( (nargin<4) || isempty(description) )
    description = 'anaMakeHdr-generated header';
end

% ---------------------------------------
ana.img = volume;
% ---------------------------------------
dims = size(ana.img);
dims = [4 dims ones(1,8)];
dims = dims(1:8);
% ---------------------------------------
if( (ndt==128) || (ndt==511) )
    dims(5) = [];
    dims = [dims 1];
end
if( ndims(ana.img) > 4 )
    error('Analyze only allows a maximum of 4 Dimension matrix');
end
% ---------------------------------------

maxval = double(max(ana.img(:)));
minval = double(min(ana.img(:)));

ana.hdr = make_header(dims, T, ndt, description, maxval, minval);
ana.filetype = 0;
ana.ext = [];
ana.untouch = 1;

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
hk.hkey_un0         = '0';

end

%---------------------------------------------------------------------
function dime = image_dimension(dims, T, ndt, maxval, minval)

dime.dim = dims;
dime.vox_units = 'mm';
dime.cal_units = '';
dime.unused1 = 0;
dime.datatype = ndt;

switch(ndt)
    case   2
        dime.bitpix = 8;
    case   4
        dime.bitpix = 16;
    case 128
        dime.bitpix = 24;
    case   {8,16}
        dime.bitpix = 32;
    case  64
        dime.bitpix = 64;
    otherwise
        error('Datatype is not supported by anaMakeHdr');
end

dime.dim_un0 = 0;

spacing = [ 0, sqrt(sum(T(1:3,1:3).*T(1:3,1:3),1)), zeros(1,7) ];
spacing = spacing(1:8);
dime.pixdim = spacing;

dime.vox_offset = 0;
dime.roi_scale = 1;
dime.funused1 = 0;
dime.funused2 = 0;
dime.cal_max = 0;
dime.cal_min = 0;
dime.compressed = 0;
dime.verified = 0;
dime.glmax = maxval;
dime.glmin = minval;

end


%---------------------------------------------------------------------
function hist = data_history( T, description )

hist.descrip = description;
hist.aux_file = 'none';
hist.orient = 0;
hist.originator = T(1:3,4)';
hist.generated = '';
hist.scannum = '';
hist.patient_id = '';
hist.exp_date = '';
hist.exp_time = '';
hist.hist_un0 = '';
hist.views = 0;
hist.vols_added = 0;
hist.start_field = 0;
hist.field_skip = 0;
hist.omax = 0;
hist.omin = 0;
hist.smax = 0;
hist.smin = 0;

end

%---------------------------------------------------------------------
function ndt = num_data_type(datatype)
switch(datatype)
    case 'uint8'
        ndt = 2;
    case 'int16'
        ndt = 4;
    case 'int32'
        ndt = 8;
    case 'single'
        ndt = 16;
    case 'double'
        ndt = 64;
    otherwise
        error('Datatype %s is not supported by anaMakeHdr',datatype);
end
end
