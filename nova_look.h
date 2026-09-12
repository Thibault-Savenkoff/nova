/* Tone curves of developed RAWs (looks): output (sRGB-encoded, 0..1) as a function of log2 of the linear
   value (LibRaw, camera white balance, no automatic brightness, 1 = white level), linear in between.
   Fitted on 10 Canon EOS 250D CR3 (test/look): 0 = canon, the camera JPEGs (Standard picture style),
   mean error 4 levels of 255; 1 = darktable, darktable 5.6 default renders, mean error 3.5. LibRaw's
   automatic brightness and plain sRGB curve were 47 and 53 away.
   darktable is also 7 % more saturated (median of the 10 files, nova_look_sat) and a bit
   greener (nova_look_gain); with both, mean error 3.35.
   ponytail: one curve per look for every camera; per-maker curves if other brands look off. */
#define NOVA_LOOK_N 58
static const float nova_look_x0 = -13.8750f, nova_look_dx = 0.250000f;
static const float nova_look[2][NOVA_LOOK_N] = {
  {
    0.00235f, 0.00235f, 0.00235f, 0.00235f, 0.00235f, 0.00235f, 0.00235f, 0.00235f,
    0.00235f, 0.00243f, 0.00290f, 0.00314f, 0.00335f, 0.00345f, 0.00348f, 0.00361f,
    0.00392f, 0.00447f, 0.00670f, 0.00940f, 0.01317f, 0.01752f, 0.02106f, 0.02594f,
    0.03228f, 0.04000f, 0.05012f, 0.05972f, 0.07385f, 0.08793f, 0.10109f, 0.11956f,
    0.14205f, 0.16951f, 0.19508f, 0.22444f, 0.25989f, 0.29299f, 0.33740f, 0.38546f,
    0.43397f, 0.48336f, 0.53831f, 0.58926f, 0.64388f, 0.69006f, 0.74376f, 0.79609f,
    0.84290f, 0.88089f, 0.91332f, 0.94297f, 0.96679f, 0.98431f, 0.99576f, 1.00000f,
    1.00000f, 1.00000f,
  },
  {
    0.00428f, 0.00428f, 0.00428f, 0.00428f, 0.00428f, 0.00428f, 0.00428f, 0.00428f,
    0.00428f, 0.00471f, 0.00516f, 0.00564f, 0.00629f, 0.00733f, 0.00819f, 0.00880f,
    0.00990f, 0.01123f, 0.01159f, 0.01315f, 0.01591f, 0.01922f, 0.02313f, 0.02838f,
    0.03486f, 0.04332f, 0.05371f, 0.06350f, 0.07943f, 0.09393f, 0.10832f, 0.12714f,
    0.14842f, 0.17179f, 0.19664f, 0.22209f, 0.25255f, 0.27787f, 0.31361f, 0.35007f,
    0.38994f, 0.43259f, 0.47733f, 0.52176f, 0.57077f, 0.61221f, 0.65512f, 0.70326f,
    0.74861f, 0.78791f, 0.82113f, 0.85231f, 0.88111f, 0.90424f, 0.92147f, 0.95690f,
    0.96619f, 0.96619f,
  },
};

/* 16-bit linear -> 16-bit display value, look 0 (canon) or 1 (darktable). */
static unsigned short nova_look_map(unsigned v, int look) {
  const float *c = nova_look[look];
  float x = v ? (log2f(v / 65535.0f) - nova_look_x0) / nova_look_dx : 0;
  int i = x < 0 ? 0 : x >= NOVA_LOOK_N - 1 ? NOVA_LOOK_N - 2 : (int)x;
  float t = x - i, y = c[i] + (c[i + 1] - c[i]) * (t < 0 ? 0 : t > 1 ? 1 : t);
  return (unsigned short)lrintf(y * 65535);
}

/* Saturation of each look, around the mean of the 3 display values. */
static const float nova_look_sat[2] = { 1.0f, 1.07f };

/* Linear gains (R, G, B) before the curve: darktable's colour calibration is a bit greener than
   LibRaw's camera white balance (2 levels of 255 on the 10 files). */
static const float nova_look_gain[2][3] = { { 1.0f, 1.0f, 1.0f }, { 0.98f, 1.0f, 0.97f } };

/* One pixel: 16-bit linear RGB -> 16-bit display RGB (lut: nova_look_map for this look). */
static void nova_look_rgb(const unsigned short *lut, const unsigned short *in, unsigned short *out, int look) {
  const float *gn = nova_look_gain[look];
  float r = lut[(unsigned)(in[0] * gn[0])], g = lut[(unsigned)(in[1] * gn[1])], b = lut[(unsigned)(in[2] * gn[2])], m, k = nova_look_sat[look];
  if (k != 1.0f) {
    m = (r + g + b) / 3;
    r = m + k * (r - m); g = m + k * (g - m); b = m + k * (b - m);
    r = r < 0 ? 0 : r > 65535 ? 65535 : r; g = g < 0 ? 0 : g > 65535 ? 65535 : g; b = b < 0 ? 0 : b > 65535 ? 65535 : b;
  }
  out[0] = lrintf(r); out[1] = lrintf(g); out[2] = lrintf(b);
}
