package openfl._internal.renderer.console;
#if lime_console


import cpp.vm.WeakRef;
import cpp.Int8;
import cpp.UInt8;
import cpp.Float32;
import lime.graphics.console.IndexBuffer;
import lime.graphics.console.PointerUtil;
import lime.graphics.console.Primitive;
import lime.graphics.console.RenderState;
import lime.graphics.console.Shader;
import lime.graphics.console.Texture;
import lime.graphics.console.TextureData;
import lime.graphics.console.TextureFilter;
import lime.graphics.console.TextureFormat;
import lime.graphics.console.VertexDecl;
import lime.graphics.console.VertexBuffer;
import lime.graphics.ConsoleRenderContext;
import lime.graphics.Image;
import lime.math.Matrix4;
import lime.text.Glyph;
import lime.text.TextLayout;
import openfl._internal.renderer.cairo.CairoTextField;
import openfl._internal.renderer.AbstractRenderer;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.BlendMode;
import openfl.display.CapsStyle;
import openfl.display.DisplayObject;
import openfl.display.DisplayObjectContainer;
import openfl.display.Graphics;
import openfl.display.JointStyle;
import openfl.display.LineScaleMode;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.display.Stage;
import openfl.display.Tilesheet;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.text.Font;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;


@:access(openfl.display.Bitmap)
@:access(openfl.display.BitmapData)
@:access(openfl.display.DisplayObject)
@:access(openfl.display.DisplayObjectContainer)
@:access(openfl.display.Graphics)
@:access(openfl.display.Sprite)
@:access(openfl.display.Stage)
@:access(openfl.display.Tilesheet)
@:access(openfl.geom.Rectangle)


class ConsoleRenderer extends AbstractRenderer {
	

	private var ctx:ConsoleRenderContext;

	private var defaultShader:Shader;
	private var fillShader:Shader;

	// TODO(james4k): move to a TransientBuffers class or something.. or move to C++
	private var indexBufferCounts:Array<Int> = [];
	private var indexBuffers:Array<IndexBuffer> = [];
	private var indexBufferAges:Array<Int8> = [];
	private var vertexBufferDecls:Array<VertexDecl> = [];
	private var vertexBufferCounts:Array<Int> = [];
	private var vertexBuffers:Array<VertexBuffer> = [];
	private var vertexBufferAges:Array<Int8> = [];

	private var textureImages:Array<WeakRef<Image>> = [];
	private var textures:Array<Texture> = [];

	private var viewProj:Matrix4;
	private var transform:Matrix4;

	private var hasFill = false;
	private var fillBitmap:BitmapData = null;
	private var fillBitmapSmooth:Bool = false;
	private var fillColor:Array<Float32> = [1, 1, 1, 1];

	private var hasStroke = false;
	private var lineWidth = 0.0;
	private var lineColor = 0;
	private var lineAlpha = 1.0;
	private var lineScaleMode = LineScaleMode.NORMAL;
	private var lineCaps = CapsStyle.ROUND;
	private var lineJoints = JointStyle.ROUND;
	private var lineMiter = 3.0;

	private var points = new Array<Float32> ();

	private var clipRect:Rectangle = null;

	#if !console_pc
	private static var pixelOffsetX:Float = 0.0;
	private static var pixelOffsetY:Float = 0.0;
	#else
	// DirectX 9 texture sampling offset
	private static var pixelOffsetX:Float = 0.5;
	private static var pixelOffsetY:Float = 0.5;
	#end

	
	public function new (width:Int, height:Int, ctx:ConsoleRenderContext) {

		this.ctx = ctx;
		
		super (width, height);
		
		this.width = width;
		this.height = height;

		defaultShader = ctx.lookupShader ("openfl_default");
		fillShader = ctx.lookupShader ("openfl_fill");

	}


	public function destroy ():Void {

		for (ib in indexBuffers) {
			ctx.destroyIndexBuffer (ib);
		}

		for (vb in vertexBuffers) {
			ctx.destroyVertexBuffer (vb);
		}

		for (tex in textures) {
			ctx.destroyTexture (tex);
		}

		indexBuffers = null;
		vertexBuffers = null;
		textures = null;

	}
	
	
	public override function render (stage:Stage):Void {

		viewProj = Matrix4.createOrtho (
			0 + pixelOffsetX,
			width + pixelOffsetY,
			height + pixelOffsetX,
			0 + pixelOffsetY,
			-1, 1
		);

		ctx.setViewport (0, 0, width, height);
		ctx.clear (
			Std.int (stage.__colorSplit[0] * 0xff),
			Std.int (stage.__colorSplit[1] * 0xff),
			Std.int (stage.__colorSplit[2] * 0xff),
			0xff
		);

		ctx.setRasterizerState (CULLNONE_SOLID);
		ctx.setDepthStencilState (DEPTHTESTOFF_DEPTHWRITEOFF_STENCILOFF);
		ctx.setBlendState (SRCALPHA_INVSRCALPHA_ONE_ZERO_RGB);

		renderDisplayObject (stage);

		collectTransientBuffers ();
		collectTextures ();

	}


	public override function resize (width:Int, height:Int):Void {

		super.resize (width, height);

		this.width = width;
		this.height = height;

	}

	
	private function renderDisplayObject (object:DisplayObject) {

		if (!object.__renderable || object.__worldAlpha <= 0) {
			return;
		}

		var prevClipRect = clipRect;
		if (object.scrollRect != null) {
			clipRect = new Rectangle (
				object.scrollRect.x,
				object.scrollRect.y,
				object.scrollRect.width,
				object.scrollRect.height
			);
			object.scrollRect.__transform (clipRect, object.__worldTransform);
			var bounds = object.getBounds (null);

			//clipRect.x += object.__worldTransform.tx;
			//clipRect.y += object.__worldTransform.ty;
			//trace ("-");
			//trace (object.__worldTransform.tx, object.__worldTransform.ty, object.width, object.height);
			//trace (object.x, object.y, object.width, object.height);
			//trace (clipRect.x, clipRect.y, clipRect.width, clipRect.height);
			//trace (bounds.x, bounds.y, bounds.width, bounds.height);
			clipRect = clipRect.intersection (bounds);
			//trace (clipRect.x, clipRect.y, clipRect.width, clipRect.height);
		}

		if (Std.is (object, DisplayObjectContainer)) {

			renderDisplayObjectContainer (cast (object));

		} else if (Std.is (object, Shape)) {

			renderShape_ (cast (object));

		} else if (Std.is (object, TextField)) {

			renderTextField (cast (object));

		}

		if (object.scrollRect != null) {
			clipRect = prevClipRect;	
		}

	}


	private function renderDisplayObjectContainer (object:DisplayObjectContainer) {

		if (Std.is (object, Sprite)) {

			renderSprite (cast (object));

		} else if (Std.is (object, Bitmap)) {

			renderBitmap (cast (object));

		}

		for (child in object.__children) {

			renderDisplayObject (child);

		}

		object.__removedChildren = [];

	}


	private function setObjectTransform (object:DisplayObject) {

		transform = Matrix4.createABCD (
			object.__worldTransform.a,
			object.__worldTransform.b,
			object.__worldTransform.c,
			object.__worldTransform.d,
			object.__worldTransform.tx,
			object.__worldTransform.ty
		);

	}


	// transientIndexBuffer returns an IndexBuffer that is only valid for the frame
	private function transientIndexBuffer (indexCount:Int):IndexBuffer {
 
		// aligned indexCount to allow for more reusability
		var align = 16;
		indexCount = (indexCount + align - 1) & ~(align - 1);

		// age of -1 to double buffer, to prevent race conditions
		// TODO(james4k): confirm this is necessary. dynamic vertex buffers are
		// double buffered internally, and dynamic index buffers are not..
		var startAge = -1;

		for (i in 0...indexBuffers.length) {

			if (indexBufferCounts[i] == indexCount &&
				indexBufferAges[i] > 0
			) {
				indexBufferAges[i] = startAge;
				return indexBuffers[i];
			}

		}

		var ib = ctx.createIndexBuffer (null, indexCount);	

		indexBufferCounts.push (indexCount);
		indexBuffers.push (ib);
		indexBufferAges.push (startAge);

		return ib;

	}


	// transientVertexBuffer returns a VertexBuffer that is only valid for the frame
	private function transientVertexBuffer (decl:VertexDecl, vertexCount:Int):VertexBuffer {
 
		// aligned vertexCount to allow for more reusability
		var align = 16;
		vertexCount = (vertexCount + align - 1) & ~(align - 1);

		// vertex buffers are double buffered internally, so can reuse every frame.
		// (compare to transientIndexBuffer)
		var startAge = 0;

		for (i in 0...vertexBuffers.length) {

			if (vertexBufferDecls[i] == decl &&
				vertexBufferCounts[i] == vertexCount &&
				vertexBufferAges[i] > 0
			) {
				vertexBufferAges[i] = startAge;
				return vertexBuffers[i];
			}

		}

		var vb = ctx.createVertexBuffer (decl, vertexCount);	

		vertexBufferDecls.push (decl);
		vertexBufferCounts.push (vertexCount);
		vertexBuffers.push (vb);
		vertexBufferAges.push (startAge);

		return vb;

	}


	private function collectTransientBuffers ():Void {

		var i = 0;

		while (i < indexBufferAges.length) {

			if (indexBufferAges[i] > 1) {

				ctx.destroyIndexBuffer (indexBuffers[i]);

				if (i == indexBufferCounts.length - 1) {
					indexBufferCounts.pop ();
					indexBuffers.pop ();
					indexBufferAges.pop ();
				} else {
					indexBufferCounts[i] = indexBufferCounts.pop ();
					indexBuffers[i] = indexBuffers.pop ();
					indexBufferAges[i] = indexBufferAges.pop ();
				}

				continue;

			}

			indexBufferAges[i]++;
			i++;

		}

		i = 0;

		while (i < vertexBufferAges.length) {

			if (vertexBufferAges[i] > 1) {

				ctx.destroyVertexBuffer (vertexBuffers[i]);

				if (i == vertexBufferDecls.length - 1) {
					vertexBufferDecls.pop ();
					vertexBufferCounts.pop ();
					vertexBuffers.pop ();
					vertexBufferAges.pop ();
				} else {
					vertexBufferDecls[i] = vertexBufferDecls.pop ();
					vertexBufferCounts[i] = vertexBufferCounts.pop ();
					vertexBuffers[i] = vertexBuffers.pop ();
					vertexBufferAges[i] = vertexBufferAges.pop ();
				}

				continue;

			}

			vertexBufferAges[i]++;
			i++;

		}

	}


	private function collectTextures ():Void {

		var i = 0;

		while (i < textureImages.length) {

			if (textureImages[i].get () == null) {

				ctx.destroyTexture (textures[i]);

				if (i == textureImages.length - 1) {
					textureImages.pop ();
					textures.pop ();
				} else {
					textureImages[i] = textureImages.pop ();
					textures[i] = textures.pop ();
				}

				continue;

			}

			i++;

		}

	}


	private function imageTexture (image:Image):Texture {

		for (i in 0...textureImages.length) {

			if (textureImages[i].get () == image) {

				var t = textures[i];

				if (image.dirty && image.buffer.data != null) {

					t.updateFromRGBA (
						cast (cpp.Pointer.arrayElem (image.buffer.data.buffer.getData (), 0))
					);

					image.dirty = false;

				}

				return t;

			}

		}

		var texture = ctx.createTexture (
			TextureFormat.ARGB,
			image.buffer.width,
			image.buffer.height,
			null
		);

		if (image.buffer.data != null) {

			texture.updateFromRGBA (
				cast (cpp.Pointer.arrayElem (image.buffer.data.buffer.getData (), 0))
			);

		}

		image.dirty = false;

		textureImages.push (new WeakRef (image));
		textures.push (texture);

		return texture;

	}


	private function renderBitmap (bitmap:Bitmap) {

		setObjectTransform (bitmap);
		transform.append (viewProj);
		transform.transpose ();

		var w = bitmap.bitmapData.width;
		var h = bitmap.bitmapData.height;
		var color:Array<cpp.Float32> = [1, 1, 1, bitmap.__worldAlpha];

		var vertexBuffer = transientVertexBuffer (VertexDecl.PositionTexcoordColor, 4);
		var out = vertexBuffer.lock ();
		out.vec3 (0, 0, 0);
		out.vec2 (0, 0);
		out.color(0xff, 0xff, 0xff, 0xff);
		out.vec3 (0, h, 0);
		out.vec2 (0, 1);
		out.color(0xff, 0xff, 0xff, 0xff);
		out.vec3 (w, 0, 0);
		out.vec2 (1, 0);
		out.color(0xff, 0xff, 0xff, 0xff);
		out.vec3 (w, h, 0);
		out.vec2 (1, 1);
		out.color(0xff, 0xff, 0xff, 0xff);
		vertexBuffer.unlock ();

		var texture = imageTexture (bitmap.bitmapData.__image);

		ctx.bindShader (defaultShader);
		ctx.setVertexShaderConstantF (0, PointerUtil.fromMatrix (transform), 4);
		ctx.setVertexShaderConstantF (4, cpp.Pointer.arrayElem (color, 0), 1);
		ctx.setVertexSource (vertexBuffer);
		ctx.setTexture (0, texture);
		ctx.setTextureAddressMode (0, Clamp, Clamp);
		ctx.draw (Primitive.TriangleStrip, 0, 2);

	}


	private function renderShape_ (shape:Shape) {

		var graphics = shape.__graphics;
		//var dirty = graphics.__dirty;
		if (graphics.__commands.length == 0) {
			return;
		}

		drawNaive (shape, graphics);

	}


	private function renderSprite (sprite:Sprite) {

		if (sprite.__graphics == null) {
			return;
		}

		draw (sprite);

	}
	
	
	private function renderTextField (tf:TextField) {
		
		//CairoTextField.render (tf);
		//TextFieldGraphics.render (tf);

		if (tf.__graphics == null) {
			return;
		}

		draw (tf);

	}


	private function draw (object:DisplayObject) {

		var graphics = object.__graphics;
		var dirty = graphics.__dirty;
		if (graphics.__commands.length == 0) {
			return;
		}

		drawNaive (object, graphics);

/*
		if (dirty) {

			//update (object, graphics);

		}

		if (object.cacheAsBitmap) {

			trace ("not implemented");

		} else {
			
			//submit ();

		}
*/

	}


	private function closePath (object:DisplayObject) {

		drawFill (object);
		drawStroke ();

		cpp.NativeArray.setSize (points, 0);

	}

	
	// div divides an integer by an integer using integer math.
	// Normally in haxe, Int divided by Int returns Float. Can't seem to be
	// avoided even with cast() or Std.int()
	private inline function div (a:Int, b:Int):Int {

		return untyped __cpp__ ("{0} / {1}", a, b);

	}




	private function drawFill (object:DisplayObject) {

		// need minimum of 3 points
		if (!hasFill || points.length < 6) {
			return;
		}

		//var triangles = new Array<Int> ();
		//PolyK.triangulate (triangles, points);

		setObjectTransform (object);
		transform.append (viewProj);
		transform.transpose ();

		var vertexCount = div (points.length, 2);
		var indexCount = (vertexCount - 2) * 3;

		var vertexBuffer = transientVertexBuffer (VertexDecl.Position, vertexCount);	
		var indexBuffer = transientIndexBuffer (indexCount);

		var out = vertexBuffer.lock ();
		for (i in 0...vertexCount) {
			out.vec3 (points[i*2 + 0], points[i*2 + 1], 0);
		}
		vertexBuffer.unlock ();

		var unsafeIndices = indexBuffer.lock ();
		for (i in 0...vertexCount-2) {
			unsafeIndices[i*3 + 0] = 0;
			unsafeIndices[i*3 + 1] = i+1;
			unsafeIndices[i*3 + 2] = i+2;
		}
		indexBuffer.unlock ();

		ctx.bindShader (fillShader);
		ctx.setVertexShaderConstantF (0, PointerUtil.fromMatrix (transform), 4);
		ctx.setVertexShaderConstantF (4, cpp.Pointer.arrayElem (fillColor, 0), 1);
		ctx.setVertexSource (vertexBuffer);
		//ctx.draw (Primitive.Triangle, 0, vertexCount - 2);
		ctx.setIndexSource (indexBuffer);
		ctx.drawIndexed (Primitive.Triangle, vertexCount, 0, div (indexCount, 3));

	}


	private function drawStroke () {

		if (!hasStroke) {
			return;
		}	

	}


	private function drawNaive (object:DisplayObject, graphics:Graphics) {

		graphics.__dirty = false;

		hasFill = false;
		hasStroke = false;
		fillColor[0] = 1.0;
		fillColor[1] = 1.0;
		fillColor[2] = 1.0;
		fillColor[3] = object.__worldAlpha;

		// TODO(james4k): set blend state based on object.blendMode

		// TODO(james4k): warn on unimplemented WindingRules

		if (clipRect != null) {

			viewProj = Matrix4.createOrtho (
				Math.floor (clipRect.x) + pixelOffsetX,
				Math.floor (clipRect.x) + Math.ceil (clipRect.width) + pixelOffsetX,
				Math.floor (clipRect.y) + Math.ceil (clipRect.height) + pixelOffsetY,
				Math.floor (clipRect.y) + pixelOffsetY,
				-1, 1
			);

			var viewport = new Rectangle (0, 0, this.width, this.height);
			viewport = viewport.intersection (clipRect);
			ctx.setViewport (
				cast (viewport.x),
				cast (viewport.y),
				cast (Math.ceil (viewport.width)),
				cast (Math.ceil (viewport.height))
			);

		}

		for (cmd in graphics.__commands) {

			switch (cmd) {

				case BeginBitmapFill (bitmap, matrix, repeat, smooth):

					hasFill = true;
					fillBitmap = bitmap;
					fillBitmapSmooth = smooth;
					fillColor[0] = 1.0;
					fillColor[1] = 1.0;
					fillColor[2] = 1.0;
					fillColor[3] = object.__worldAlpha;

					// TODO(james4k): deal with matrix, repeat

				case BeginFill (rgb, alpha):

					// TODO(james4k): color transform. no sense doing that in shader for fill, right?
					hasFill = true;
					fillBitmap = null;
					fillColor[0] = ((rgb >> 16) & 0xFF) / 255.0;
					fillColor[1] = ((rgb >> 8) & 0xFF) / 255.0;
					fillColor[2] = ((rgb >> 0) & 0xFF) / 255.0;
					fillColor[3] = alpha * object.__worldAlpha;

				// LineStyle (thickness:Null<Float>, color:Null<Int>, alpha:Null<Float>, pixelHinting:Null<Bool>,
				//            scaleMode:LineScaleMode, caps:CapsStyle, joints:JointStyle, miterLimit:Null<Float>);
				case LineStyle (thickness, color, alpha, pixelHinting, scaleMode, caps, joints, miterLimit):

					//closePath (object);

					if (thickness == null) {
						hasStroke = false;
						continue;
					}

					hasStroke = true;

					lineWidth = thickness;
					lineColor = color == null ? 0 : color;
					lineAlpha = alpha == null ? 1 : alpha;
					lineScaleMode = scaleMode;
					lineCaps = caps;
					lineJoints = joints;
					lineMiter = miterLimit == null ? 3 : miterLimit;
					// TODO(james4k): pixelHinting
					
					
				case LineTo (x, y):

					points.push (x);
					points.push (y);

				case MoveTo (x, y):

					closePath (object);

					points.push (x);
					points.push (y);

				case EndFill:

					closePath (object);

					hasFill = false;
					hasStroke = false;
					fillBitmap = null;
					fillColor[0] = 1.0;
					fillColor[1] = 1.0;
					fillColor[2] = 1.0;
					fillColor[3] = object.__worldAlpha;

				case DrawCircle (x, y, radius):

					// TODO(james4k): replace with 2? curveTo calls

					drawEllipse (object, x, y, radius, radius);

				case DrawEllipse (x, y, width, height):

					// TODO(james4k): replace with 2? curveTo calls

					drawEllipse (object, x + width*0.5, y + height*0.5, width*0.5, height*0.5);

				case DrawRect (x, y, width, height):

					if (!hasFill || fillBitmap != null) {
						// TODO(james4k): fillBitmap, stroke
						trace ("unsupported DrawRect");
						continue;
					}

					// TODO(james4k): replace moveTo/lineTo calls

					setObjectTransform (object);
					transform.append (viewProj);
					transform.transpose ();

					var vertexBuffer = transientVertexBuffer (VertexDecl.Position, 4);	
					var out = vertexBuffer.lock ();
					out.vec3 (x, y, 0);
					out.vec3 (x, y + height, 0);
					out.vec3 (x + width, y, 0);
					out.vec3 (x + width, y + height, 0);
					vertexBuffer.unlock ();

					ctx.bindShader (fillShader);
					ctx.setVertexShaderConstantF (0, PointerUtil.fromMatrix (transform), 4);
					ctx.setVertexShaderConstantF (4, cpp.Pointer.arrayElem (fillColor, 0), 1);
					ctx.setVertexSource (vertexBuffer);
					ctx.draw (Primitive.TriangleStrip, 0, 2);

				case DrawRoundRect (x, y, width, height, rx, ry):

					if (!hasFill || fillBitmap != null) {
						// TODO(james4k): fillBitmap, stroke
						trace ("unsupported DrawRoundRect");
						continue;
					}

					// TODO(james4k): replace with lineTo/curveTo calls

					if (ry == -1) ry = rx;
					
					rx *= 0.5;
					ry *= 0.5;
					
					if (rx > width / 2) rx = width / 2;
					if (ry > height / 2) ry = height / 2;

					var points = new Array<Float> ();
					GraphicsPaths.roundRectangle (points, x, y, width, height, rx, ry);

					if (hasFill) {

						var triangles = new Array<Int> ();
						PolyK.triangulate (triangles, points);

						setObjectTransform (object);
						transform.append (viewProj);
						transform.transpose ();

						var vertexCount = div (points.length, 2);
						var indexCount = triangles.length;

						var vertexBuffer = transientVertexBuffer (VertexDecl.Position, vertexCount);	
						var indexBuffer = transientIndexBuffer (indexCount);

						var out = vertexBuffer.lock ();
						for (i in 0...div (points.length, 2)) {
							out.vec3 (points[i*2], points[i*2 + 1], 0);
						}
						vertexBuffer.unlock ();

						var unsafeIndices = indexBuffer.lock ();
						for (i in 0...triangles.length) {
							unsafeIndices[i] = triangles[i];
						}
						indexBuffer.unlock ();

						ctx.bindShader (fillShader);
						ctx.setVertexShaderConstantF (0, PointerUtil.fromMatrix (transform), 4);
						ctx.setVertexShaderConstantF (4, cpp.Pointer.arrayElem (fillColor, 0), 1);
						ctx.setVertexSource (vertexBuffer);
						ctx.setIndexSource (indexBuffer);
						ctx.drawIndexed (Primitive.Triangle, vertexCount, 0, div (triangles.length, 3));
						//ctx.draw (Primitive.TriangleStrip, 0, div (triangles.length, 3));

					}

				case DrawTiles (sheet, tileData, smooth, flags, count):

					var useScale = (flags & Tilesheet.TILE_SCALE) != 0;
					var useRotation = (flags & Tilesheet.TILE_ROTATION) != 0;
					var useTransform = (flags & Tilesheet.TILE_TRANS_2x2) != 0;
					var useRGB = (flags & Tilesheet.TILE_RGB) != 0;
					var useAlpha = (flags & Tilesheet.TILE_ALPHA) != 0;
					var useRect = (flags & Tilesheet.TILE_RECT) != 0;
					var useOrigin = (flags & Tilesheet.TILE_ORIGIN) != 0;

					var blendMode:BlendMode = switch(flags & 0xF0000) {
						case Tilesheet.TILE_BLEND_ADD:		ADD;
						case Tilesheet.TILE_BLEND_MULTIPLY:	MULTIPLY;
						case Tilesheet.TILE_BLEND_SCREEN:	SCREEN;
						case _:								NORMAL;
					};

					if (blendMode != BlendMode.NORMAL) {
						trace ("DrawTiles not implemented for BlendMode: " + blendMode);
					}

					if (useTransform) {
						useScale = false;
						useRotation = false;
					}

					var scaleIndex = 0;
					var rotationIndex = 0;
					var transformIndex = 0;
					var rgbIndex = 0;
					var alphaIndex = 0;

					var stride = 3;
					if (useRect) {
						stride = useOrigin ? 8 : 6;
					}
					if (useScale) {
						scaleIndex = stride;
						stride += 1;
					}
					if (useRotation) {
						rotationIndex = stride;
						stride += 1;
					}
					if (useTransform) {
						transformIndex = stride;
						stride += 4;
					}
					if (useRGB) {
						rgbIndex = stride;
						stride += 3;
					}
					if (useAlpha) {
						alphaIndex = stride;
						stride += 1;
					}

					var totalCount = tileData.length;
					if (count >= 0 && totalCount > count) {
						totalCount = count;
					}
					var itemCount = div (totalCount, stride);
					if (itemCount <= 0) {
						continue;
					}

					var tileID = -1;
					var rect:Rectangle = sheet.__rectTile;
					var tileUV:Rectangle = sheet.__rectUV;
					var center:Point = sheet.__point;

					var vertexCount = itemCount * 4;
					var vertexBuffer = transientVertexBuffer (VertexDecl.PositionTexcoordColor, vertexCount);	
					var out = vertexBuffer.lock ();

					for (itemIndex in 0...itemCount) {

						var index = itemIndex * stride;

						var x = tileData[index + 0];
						var y = tileData[index + 1];

						if (useRect) {

							tileID = -1;

							rect.x = tileData[index + 2];
							rect.y = tileData[index + 3];
							rect.width = tileData[index + 4];
							rect.height = tileData[index + 5];
							
							if (useOrigin) {
								center.x = tileData[index + 6];
								center.y = tileData[index + 7];
							} else {
								center.setTo(0, 0);
							}
							
							tileUV.setTo(
								rect.left / sheet.__bitmap.width,
								rect.top / sheet.__bitmap.height,
								rect.right / sheet.__bitmap.width,
								rect.bottom / sheet.__bitmap.height
							);

						} else {

							tileID = Std.int (tileData[index + 2]);
							rect = sheet.getTileRect(tileID);	
							center = sheet.getTileCenter(tileID);	
							tileUV = sheet.getTileUVs(tileID);	

						}

						if (rect == null || rect.width <= 0 || rect.height <= 0 || center == null) {
							continue;
						}	

						var alpha = object.__worldAlpha;
						var red:UInt8 = 255, green:UInt8 = 255, blue:UInt8 = 255;
						var scale = 1.0;
						var rotation = 0.0;
						var a = 0.0, b = 0.0, c = 0.0, d = 0.0, tx = 0.0, ty = 0.0;

						if (useRGB) {
							// TODO(james4k): premultiplied alpha?
							red   = Std.int (tileData[index + rgbIndex + 0] * 255);
							green = Std.int (tileData[index + rgbIndex + 1] * 255);
							blue  = Std.int (tileData[index + rgbIndex + 2] * 255);
						}

						if (useAlpha) {
							alpha *= tileData[index + alphaIndex];	
						}

						if (useScale) {
							scale = tileData[index + scaleIndex];
						}

						if (useRotation) {
							rotation = tileData[index + rotationIndex];
						}

						if (useTransform) {
							a = tileData[index + transformIndex + 0];
							b = tileData[index + transformIndex + 1];
							c = tileData[index + transformIndex + 2];
							d = tileData[index + transformIndex + 3];
						} else {
							a = scale * Math.cos (rotation);
							b = scale * Math.sin (rotation);
							c = -b;
							d = a;
						}

						var tx = x - (center.x * a + center.y * c);
						var ty = y - (center.x * b + center.y * d);

						var w0 = rect.width * 1.0;
						var w1 = 0.0;
						var h0 = rect.height * 1.0;
						var h1 = 0.0;

						// tileUV.width, height are actually x1, y1

						out.vec3 (a*w1 + c*h1 + tx, d*h1 + b*w1 + ty, 0);
						out.vec2 (tileUV.x, tileUV.y);
						out.color (red, green, blue, Std.int(alpha * 0xff));

						out.vec3 (a*w0 + c*h1 + tx, d*h1 + b*w0 + ty, 0);
						out.vec2 (tileUV.width, tileUV.y);
						out.color (red, green, blue, Std.int(alpha * 0xff));

						out.vec3 (a*w0 + c*h0 + tx, d*h0 + b*w0 + ty, 0);
						out.vec2 (tileUV.width, tileUV.height);
						out.color (red, green, blue, Std.int(alpha * 0xff));

						out.vec3 (a*w1 + c*h0 + tx, d*h0 + b*w1 + ty, 0);
						out.vec2 (tileUV.x, tileUV.height);
						out.color (red, green, blue, Std.int(alpha * 0xff));

					}

					vertexBuffer.unlock ();

					var indexBuffer = transientIndexBuffer (itemCount * 6);
					var unsafeIndices = indexBuffer.lock ();
					for (i in 0...itemCount) {
						unsafeIndices[i*6 + 0] = i*4 + 0;
						unsafeIndices[i*6 + 1] = i*4 + 1;
						unsafeIndices[i*6 + 2] = i*4 + 2;
						unsafeIndices[i*6 + 3] = i*4 + 0;
						unsafeIndices[i*6 + 4] = i*4 + 3;
						unsafeIndices[i*6 + 5] = i*4 + 2;
					}
					indexBuffer.unlock ();

					setObjectTransform (object);
					transform.append (viewProj);
					transform.transpose ();

					var texture = imageTexture (sheet.__bitmap.__image);

					ctx.bindShader (defaultShader);
					ctx.setVertexShaderConstantF (0, PointerUtil.fromMatrix (transform), 4);
					ctx.setVertexShaderConstantF (4, cpp.Pointer.arrayElem (fillColor, 0), 1);
					ctx.setVertexSource (vertexBuffer);
					ctx.setIndexSource (indexBuffer);
					ctx.setTexture (0, texture);
					ctx.setTextureAddressMode (0, Clamp, Clamp);
					if (smooth) {
						ctx.setTextureFilter (0, TextureFilter.Linear, TextureFilter.Linear);
					} else {
						ctx.setTextureFilter (0, TextureFilter.Nearest, TextureFilter.Nearest);
					}
					ctx.drawIndexed (Primitive.Triangle, vertexCount, 0, itemCount * 2);

				case DrawTriangles (vertices, indices, uvtData, culling, colors, blendMode):

					if (!hasFill || fillBitmap == null) {
						trace ("DrawTriangles without bitmap fill");
						continue;
					}

					if (vertices.length <= 0 || indices.length <= 0) {
						continue;
					}

					setObjectTransform (object);
					transform.append (viewProj);
					transform.transpose ();

					var texture = imageTexture (fillBitmap.__image);

					var vertexCount = div (vertices.length, 2);
					var vertexBuffer = transientVertexBuffer (VertexDecl.PositionTexcoordColor, vertexCount);	
					var out = vertexBuffer.lock ();
					var i = 0;
					while (i < vertices.length) {
						out.vec3 (vertices[i], vertices[i+1], 0);
						out.vec2 (uvtData[i], uvtData[i+1]);
						// TODO(james4k): color
						out.color (0xff, 0xff, 0xff, 0xff);
						i += 2;
					}
					vertexBuffer.unlock ();
					
					var indexBuffer = transientIndexBuffer (indices.length);
					var unsafeIndices = indexBuffer.lock ();
					for (i in 0...indices.length) {
						unsafeIndices[i] = indices[i];
					}
					indexBuffer.unlock ();

					ctx.bindShader (defaultShader);
					ctx.setVertexShaderConstantF (0, PointerUtil.fromMatrix (transform), 4);
					ctx.setVertexShaderConstantF (4, cpp.Pointer.arrayElem (fillColor, 0), 1);
					ctx.setVertexSource (vertexBuffer);
					ctx.setIndexSource (indexBuffer);
					ctx.setTexture (0, texture);
					// TODO(james4k): BunnyMark's usage wants wrapped textures. do we ever use clamped?
					ctx.setTextureAddressMode (0, Wrap, Wrap);
					if (fillBitmapSmooth) {
						ctx.setTextureFilter (0, TextureFilter.Linear, TextureFilter.Linear);
					} else {
						ctx.setTextureFilter (0, TextureFilter.Nearest, TextureFilter.Nearest);
					}
					ctx.drawIndexed (Primitive.Triangle, vertexCount, 0, div (indices.length, 3));

				default:

					trace ("not implemented: " + cmd);

/*

	COMMANDS TODO

	CubicCurveTo (controlX1:Float, controlY1:Float, controlX2:Float, controlY2:Float, anchorX:Float, anchorY:Float);
	CurveTo (controlX:Float, controlY:Float, anchorX:Float, anchorY:Float);
	DrawPathC(commands:Vector<Int>, data:Vector<Float>, winding:GraphicsPathWinding);
	OverrideMatrix(matrix:Matrix);

*/

			}
	
		}

		if (points.length > 0) {
			closePath (object);
		}

		if (clipRect != null) {

			viewProj = Matrix4.createOrtho (
				0 + pixelOffsetX,
				this.width + pixelOffsetX,
				this.height + pixelOffsetY,
				0 + pixelOffsetY,
				-1, 1
			);

			ctx.setViewport (0, 0, this.width, this.height);

		}

	}

	private function drawEllipse (object:DisplayObject, x:Float, y:Float, rx:Float, ry:Float) {

		if (!hasFill || fillBitmap != null) {
			// TODO(james4k): fillBitmap, stroke
			trace ("unsupported drawEllipse");
			return;
		}

		var segments:Int = cast (0.334 * 2 * Math.PI * Math.max (rx, ry));
		var points = new Array<Float> ();
		GraphicsPaths.ellipse (points, x, y, rx, ry, segments);

		if (hasFill) {

			//var triangles = new Array<Int> ();
			//PolyK.triangulate (triangles, points);

			setObjectTransform (object);
			transform.append (viewProj);
			transform.transpose ();

			var vertexCount = div (points.length, 2) + 1;
			var indexCount = (vertexCount - 2) * 3;

			var vertexBuffer = transientVertexBuffer (VertexDecl.Position, vertexCount);	
			var indexBuffer = transientIndexBuffer (indexCount);

			var out = vertexBuffer.lock ();
			out.vec3 (x, y, 0);
			for (i in 0...vertexCount) {
				out.vec3 (points[i*2 + 0], points[i*2 + 1], 0);
			}
			vertexBuffer.unlock ();

			var unsafeIndices = indexBuffer.lock ();
			for (i in 0...vertexCount-2) {
				unsafeIndices[i*3 + 0] = 0;
				unsafeIndices[i*3 + 1] = i+1;
				unsafeIndices[i*3 + 2] = i+2;
			}
			indexBuffer.unlock ();

			ctx.bindShader (fillShader);
			ctx.setVertexShaderConstantF (0, PointerUtil.fromMatrix (transform), 4);
			ctx.setVertexShaderConstantF (4, cpp.Pointer.arrayElem (fillColor, 0), 1);
			ctx.setVertexSource (vertexBuffer);
			//ctx.draw (Primitive.Triangle, 0, vertexCount - 2);
			ctx.setIndexSource (indexBuffer);
			ctx.drawIndexed (Primitive.Triangle, vertexCount, 0, div (indexCount, 3));

		}

	}

	
	
}


#else


import lime.graphics.ConsoleRenderContext;
import openfl._internal.renderer.AbstractRenderer;
import openfl.display.Stage;


class ConsoleRenderer extends AbstractRenderer {
	

	public function new (width:Int, height:Int, ctx:ConsoleRenderContext) {
		
		super (width, height);

		throw "ConsoleRenderer not supported";

	}
	
	
	public override function render (stage:Stage):Void {



	}


}

	
#end