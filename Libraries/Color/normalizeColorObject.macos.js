/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 * @format
 * @flow strict-local
 */

'use strict';

const normalizeColor = require('normalizeColor');

export type NativeOrDynamicColorType = {
  semantic?: string,
  dynamic?: {
    light: ?(string | number | NativeOrDynamicColorType),
    dark: ?(string | number | NativeOrDynamicColorType),
  },
};

function normalizeColorObject(
  color: ?NativeOrDynamicColorType,
): ?(number | NativeOrDynamicColorType) {
  if ('semantic' in color) {
    // a macos semantic color
    return color;
  } else if ('dynamic' in color && color.dynamic !== undefined) {
    // a dynamic, appearance aware color
    const dynamic = color.dynamic;
    const dynamicColor: NativeOrDynamicColorType = {
      dynamic: {
        light: normalizeColor(dynamic.light),
        dark: normalizeColor(dynamic.dark),
      },
    };
    return dynamicColor;
  }
}

module.exports = normalizeColorObject;