/*
 * sfpi_postinclude.h — Fixups that must come after sfpi.h is fully loaded
 *
 * Include this AFTER sfpi.h. With __INT32_TYPE__=long, uint32_t becomes
 * unsigned long which doesn't match vInt's existing operator overloads
 * for int32_t(=long), int, or unsigned(=unsigned int). Add the missing
 * uint32_t(=unsigned long) overloads.
 */
#pragma once
#ifdef __clang__

namespace sfpi {
sfpi_inline vInt operator&(vInt a, uint32_t b) { return a & vInt(b); }
sfpi_inline vInt operator|(vInt a, uint32_t b) { return a | vInt(b); }
sfpi_inline vInt operator^(vInt a, uint32_t b) { return a ^ vInt(b); }
} // namespace sfpi

#endif /* __clang__ */
