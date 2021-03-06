// dmd -I~/Documents/scid/generated/headers -m32 -c franco/types.d

module franco.types;

import std.stdio;
import std.math;

import scid.matrix;
import franco.matrix;
import franco.utils;

enum BgModel
{
	Cov, // covariance matrix
	Parzen // Parzen window
}

struct francoPhoto(Tmat, Timg) {
	Tmat intrinsics[9];
	Tmat extrinsics[12];
	int width;
	int height;
	Timg *image;
	Timg *background;
}

extern (C) alias francoPhotofub = francoPhoto!(float, ubyte);
extern (C) alias francoPhotofui = francoPhoto!(float, int);

struct francoParam(T) {
	T pD;
	T pFA;
	int k;
	int kbg;
}

extern (C) alias francoParamf = francoParam!float;

struct francoVoxel(T) {
	T side;
	int numVoxels;
	T center[3];
	T *pdf;
}

extern (C) alias francoVoxelf = francoVoxel!float;


class photoModel(Tmat, Timg) {
public:
	this() {
	}
	
	this(in francoPhoto!(Tmat, Timg) fp) {
		setFromFrancoPhoto(fp);
		_mvnmap = matrix!Tmat(w, h, Tmat.nan);
	}
	
	void setFromFrancoPhoto(in ref francoPhoto!(Tmat, Timg) fp) {
		_intrinsics = matrix!Tmat(3, 3);
		_intrinsics.array = fp.intrinsics.dup;
		_extrinsics = matrix!Tmat(3, 4);
		_extrinsics.array = fp.extrinsics.dup;
		
		auto extrinsics4x4 = _extrinsics.concatVertical(MatrixView!Tmat([0, 0, 0, 1], 1, 4));
		auto extrinsicsInv4x4 = extrinsics4x4.inv;
		_extrinsicsInv = matrix!Tmat(3, 4);
		foreach(i; 0..3) {
			foreach(j; 0..4) {
				_extrinsicsInv[i, j] = extrinsicsInv4x4[i, j];
			}
		}
		
		int w = fp.width;
		int h = fp.height;
		_image = matrix!Timg(w, h);
		_image.array[0..h*w] = fp.image[0..h*w];
		_background = matrix!Timg(w, h);
		_background.array[0..h*w] = fp.background[0..h*w];
	}
	
	Tmat isBack(T, uint Tsize, BgModel M)(MatrixView!T pos, int k) {
		static if(M == BgModel.Cov) {
			auto mvn = _mvnmap[pos[0, 0], pos[1, 0]];
			if(!isNaN(mvn)) return mvn;
			
			auto fore = toArray!(Tmat, Tsize)(foreground(pos));
			
			auto ns = neighbors(pos, w, h, k);
			Tmat[Tsize][] backArray;
			
			foreach(ref neighbor; ns) {
				backArray ~= toArray!(Tmat, Tsize)(background(neighbor));
			}
			
			auto m = mean!(Tmat, Tsize)(backArray);
			auto cov = covariance!(Tmat, Tsize)(backArray, m);
			mvn = mvnpdf!(Tmat, Tsize)(fore, m, cov);
			_mvnmap[pos[0, 0], pos[1, 0]] = mvn;
			return mvn;
		} else static if(M == BgModel.Parzen) {
			auto mvn = _mvnmap[pos[0, 0], pos[1, 0]];
			if(!isNaN(mvn)) return mvn;
			
			auto fore = toArray!(Tmat, Tsize)(foreground(pos));
			
			auto ns = neighbors(pos, w, h, k);
			
			mvn = 0;
			foreach(ref neighbor; ns) {
				auto back = toArray!(Tmat, Tsize)(background(neighbor));
				Tmat diffSq = 0;
				foreach(i; 0..Tsize) {
					diffSq += (fore[i] - back[i]) * (fore[i] - back[i]);
				}
				mvn += normpdf!(Tmat)(sqrt(diffSq), 0, 3);
			}
			mvn /= ns.length;
			
			_mvnmap[pos[0, 0], pos[1, 0]] = mvn;
			return mvn;
		}
	}
	
	T[N] toArray(T, uint N)(Timg pixel) {
		T[N] rgb;
		Timg rawrgb = pixel;
		
		foreach(i; 0..N) {
			rgb[i] = cast(T)(rawrgb & 255);
			rawrgb = rawrgb >> 8;
		}
		
		return rgb;
	}
	
	// image is transposed
	Timg foreground(T)(MatrixView!T pos) {
		return foreground(pos[0, 0], pos[1, 0]);
	}
	
	Timg foreground(T)(T x, T y) {
		return _image[cast(typeof(_image.rows))x, cast(typeof(_image.cols))y];
	}
	
	// image is transposed
	Timg background(T)(MatrixView!T pos) {
		return background(pos[0, 0], pos[1, 0]);
	}
	
	Timg background(T)(T x, T y) {
		return _background[cast(typeof(_background.rows))x, cast(typeof(_background.cols))y];
	}
	
	@property {
		uint w() const {
			return _image.rows;
		}
		uint h() const {
			return _image.cols;
		}
		MatrixView!Tmat intrinsics() const {
			return _intrinsics.copy;
		}
		MatrixView!Tmat extrinsics() const {
			return _extrinsics.copy;
		}
		MatrixView!Tmat projection() const {
			return _intrinsics.mul(_extrinsicsInv);
		}
	}
	
private:
	MatrixView!Tmat _intrinsics;
	MatrixView!Tmat _extrinsics;
	MatrixView!Tmat _extrinsicsInv;
	MatrixView!Timg _image; // transposed
	MatrixView!Timg _background; // transposed
	MatrixView!Tmat _mvnmap; // transposed
}

class voxelLike(Tmat, Timg, BgModel M) {
public:
	this() {
	}
	
	void setDimensions(Tmat side, MatrixView!Tmat center, int numVoxels) {
		_side = side;
		_voxelSide = side / numVoxels;
		_center = center.copy;
		_numVoxels = numVoxels;
		pdf.length = numVoxels * numVoxels * numVoxels;
	}
	
	MatrixView!Tmat indexToPosition(int index) {
		Tmat[3] position;
		position[0] = index % _numVoxels - _numVoxels / 2;
		position[1] = (index / _numVoxels) % _numVoxels - _numVoxels / 2;
		position[2] = index / (_numVoxels * _numVoxels) - _numVoxels / 2;
		position[] *= _voxelSide;
		return point3!Tmat(position).add(_center);
	}
	
	MatrixView!Tmat toHomogeneous(MatrixView!Tmat p) {
		assert((p.rows == 2 || p.rows == 3) && (p.cols == 1));
		
		MatrixView!Tmat ph;
		if(p.rows == 2) {
			ph = matrix!Tmat(3, 1);
			ph.array = p.array.dup;
			ph.array.length = 3;
			ph[2, 0] = 1.0;
		} else if(p.rows == 3) {
			ph = matrix!Tmat(4, 1);
			ph.array = p.array.dup;
			ph.array.length = 4;
			ph[3, 0] = 1.0;
		}
		return ph;
	}
	
	void reconstruct() {
		foreach(i, ref p; pdf) {
			Tmat pFill = 1;
			Tmat pNofill = 1;
			uint updateCount;
			foreach(ref model; _models) {
				auto pixel = model.projection.mul(toHomogeneous(indexToPosition(i)));
				int x = cast(int)(pixel[0, 0] / pixel[2, 0]);
				int y = cast(int)(pixel[1, 0] / pixel[2, 0]);
				
				if(pixel[2, 0] > 0) {
					continue;
				}
				
				auto ns = neighbors(x, y, model.w, model.h, _k);
				
				if(ns.length > 0) {
					updateCount++;
				}
				
				foreach(ref neighbor; ns) {
					// due to limitation of floating point range, use only the ratio
					// originally:
					// pFill *= p1
					// pNofill *= p0
					Tmat p1, p0;
					Tmat isb;
					static if(Timg.sizeof == 1) {
						isb = model.isBack!(int, 1, M)(neighbor, _kbg);
					} else static if(Timg.sizeof == 4) {
						isb = model.isBack!(int, 3, M)(neighbor, _kbg);
					}
					Tmat pR = 0.5;
					p1 = _pD * (1.0 / 255) + (1 - _pD) * isb;
					p0 = ((_pD * pR + _pFA * (1 - pR)) * (1.0 / 255) + ((1 - _pD) * pR + (1 - _pFA) * (1 - pR)) * isb);
					pFill *= p1 / p0;
				}
			}
			// just one perspective is not sufficient
			if(updateCount > 1) {
				p = pFill / (pFill + pNofill);
			} else {
				p = 0;
			}
		}
	}
	
	@property {
		void parameters(francoParam!Tmat fparam) {
			_pD = fparam.pD;
			_pFA = fparam.pFA;
			_k = fparam.k;
			_kbg = fparam.kbg;
		}
		
		// set model pointer and initialize
		void models(photoModel!(Tmat, Timg)[] m) {
			_models = m;
			
			Tmat[3] minxyz = [1e10, 1e10, 1e10];
			Tmat[3] maxxyz = [-1e10, -1e10, -1e10];
			photoModel!(Tmat, Timg)[3] minModel;
			photoModel!(Tmat, Timg)[3] maxModel;
			
			foreach(ref model; _models) {
				foreach(i; 0..3) {
					if(model.extrinsics[i, 3] < minxyz[i]) {
						minxyz[i] = model.extrinsics[i, 3];
						minModel[i] = model;
					}
					if(model.extrinsics[i, 3] > maxxyz[i]) {
						maxxyz[i] = model.extrinsics[i, 3];
						maxModel[i] = model;
					}
				}
			}
			// find largest difference in xyz
			Tmat[3] diffxyz;
			diffxyz[] = maxxyz[] - minxyz[];
			diffxyz.writeln;
			
			Tmat length = 0;
			int edgeDim;
			foreach(i; 0..2) {
				if(diffxyz[i] > length) {
					edgeDim = i;
					length = diffxyz[i];
				}
			}
			// center is on the centroid
			Tmat[3] center = [0, 0, 0];
			foreach(i; 0..3) {
				foreach(ref model; _models) {
					center[i] += model.extrinsics[i, 3];
				}
			}
			center[] /= _models.length;
			center[1] += length*0.125/2;
			center.writeln;
			setDimensions(length * 0.25, point3!Tmat(center), 50);
		}
		
		francoVoxel!Tmat fVoxel() {
			francoVoxel!Tmat fv;
			fv.side = _side;
			fv.numVoxels = _numVoxels;
			fv.center[0] = _center[0, 0];
			fv.center[1] = _center[1, 0];
			fv.center[2] = _center[2, 0];
			fv.pdf = pdf.ptr;
			return fv;
		}
	}
	
	Tmat _pD, _pFA;
	int _k, _kbg;
	
private:
	photoModel!(Tmat, Timg)[] _models;
	Tmat _side;
	Tmat _voxelSide;
	MatrixView!Tmat _center;
	int _numVoxels;
	Tmat[] pdf;
}
