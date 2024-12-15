RenFont* ren_load_font(const char *filename, float size) {
	RenFont *font = NULL;
	FILE *fp = NULL;

	/* init font */
	font = check_alloc(calloc(1, sizeof(RenFont)));
	font->size = size;

	/* load font into buffer */
	fp = fopen(filename, "rb");
	if (!fp) { return NULL; }
	/* get size */
	fseek(fp, 0, SEEK_END); int buf_size = ftell(fp); fseek(fp, 0, SEEK_SET);
	/* load */
	font->data = check_alloc(malloc(buf_size));
	int _ = fread(font->data, 1, buf_size, fp); (void) _;
	fclose(fp);
	fp = NULL;

	/* init stbfont */
	int ok = stbtt_InitFont(&font->stbfont, font->data, 0);
	if (!ok) { goto fail; }

	/* get height and scale */
	int ascent, descent, linegap;
	stbtt_GetFontVMetrics(&font->stbfont, &ascent, &descent, &linegap);
	float scale = stbtt_ScaleForMappingEmToPixels(&font->stbfont, size);
	font->height = (ascent - descent + linegap) * scale + 0.5;

	/* make tab and newline glyphs invisible by making them zero-width */
	stbtt_bakedchar *g = get_glyphset(font, '\n')->glyphs;
	g['\t'].x1 = g['\t'].x0;
	g['\n'].x1 = g['\n'].x0;

	return font;

fail:
	if (fp) { fclose(fp); }
	if (font) { free(font->data); }
	free(font);
	return NULL;
}


static GlyphSet* get_glyphset(RenFont *font, int codepoint) {
	int idx = (codepoint >> 8) % MAX_GLYPHSET;
	if (!font->sets[idx]) {
		font->sets[idx] = load_glyphset(font, idx);
	}
	return font->sets[idx];
}


static GlyphSet* load_glyphset(RenFont *font, int idx) {
	GlyphSet *set = check_alloc(calloc(1, sizeof(GlyphSet)));

	/* init image */
	int width = 128;
	int height = 128;
retry:
	set->image = ren_new_image(width, height);

	/* load glyphs */
	float s =
		stbtt_ScaleForMappingEmToPixels(&font->stbfont, 1) /
		stbtt_ScaleForPixelHeight(&font->stbfont, 1);
	int res = stbtt_BakeFontBitmap(
		font->data, 0, font->size * s, (void*) set->image->pixels,
		width, height, idx * 256, 256, set->glyphs);

	/* retry with a larger image buffer if the buffer wasn't large enough */
	if (res < 0) {
		width *= 2;
		height *= 2;
		ren_free_image(set->image);
		goto retry;
	}

	/* adjust glyph yoffsets and xadvance */
	int ascent, descent, linegap;
	stbtt_GetFontVMetrics(&font->stbfont, &ascent, &descent, &linegap);
	float scale = stbtt_ScaleForMappingEmToPixels(&font->stbfont, font->size);
	int scaled_ascent = ascent * scale + 0.5;
	for (int i = 0; i < 256; i++) {
		set->glyphs[i].yoff += scaled_ascent;
		set->glyphs[i].xadvance = floor(set->glyphs[i].xadvance);
	}

	/* convert 8bit data to 32bit */
	for (int i = width * height - 1; i >= 0; i--) {
		uint8_t n = *((uint8_t*) set->image->pixels + i);
		set->image->pixels[i] = (RenColor) { .r = 255, .g = 255, .b = 255, .a = n };
	}

	return set;
}

