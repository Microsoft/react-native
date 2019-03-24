/**
 * Copyright (c) 2015-present, Facebook, Inc.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 *
 * This is a controlled component version of RCTPickerIOS
 *
 * @format
 * @flow
 */

// TODO(macOS ISS#2323203)

'use strict';

var NativeMethodsMixin = require('NativeMethodsMixin');
var React = require('React');
const PropTypes = require('prop-types');
var StyleSheet = require('StyleSheet');
var View = require('View');
var processColor = require('processColor');

var createReactClass = require('create-react-class');
var requireNativeComponent = require('requireNativeComponent');

type PickerIOSProps = $ReadOnly<{|
  ...ViewProps,
  children: React.ChildrenArray<React.Element<typeof PickerIOSItem>>,
  itemStyle?: ?TextStyleProp,
  onChange?: ?(event: PickerIOSChangeEvent) => mixed,
  onValueChange?: ?(newValue: any, newIndex: number) => mixed,
  selectedValue: any,
|}>;

var PickerIOS = createReactClass({
  displayName: 'PickerIOS',
  mixins: [NativeMethodsMixin],

  getInitialState: function() {
    return this._stateFromProps(this.props);
  },

  componentWillReceiveProps: function(nextProps: PickerIOSProps) {
    this.setState(this._stateFromProps(nextProps));
  },

  _picker: {},

  // Translate PickerIOS prop and children into stuff that RCTPickerIOS understands.
  _stateFromProps: function(props) {
    var selectedIndex = 0;
    var items = [];
    React.Children.toArray(props.children).forEach(function(child, index) {
      if (child.props.value === props.selectedValue) {
        selectedIndex = index;
      }
      items.push({
        value: child.props.value,
        label: child.props.label,
        textColor: processColor(child.props.color),
      });
    });
    return {selectedIndex, items};
  },

  render: function() {
    return (
      <View style={this.props.style}>
        <RCTPickerIOS
          ref={
            /* $FlowFixMe(>=0.53.0 site=react_native_fb,react_native_oss) */
            picker => (this._picker = picker)
          }
          style={[styles.pickerIOS, this.props.itemStyle]}
          items={this.state.items}
          selectedIndex={this.state.selectedIndex}
          onChange={this._onChange}
          onStartShouldSetResponder={() => true}
          onResponderTerminationRequest={() => false}
        />
      </View>
    );
  },

  _onChange: function(event) {
    if (this.props.onChange) {
      this.props.onChange(event);
    }
    if (this.props.onValueChange) {
      this.props.onValueChange(
        event.nativeEvent.newValue,
        event.nativeEvent.newIndex,
      );
    }

    // The picker is a controlled component. This means we expect the
    // on*Change handlers to be in charge of updating our
    // `selectedValue` prop. That way they can also
    // disallow/undo/mutate the selection of certain values. In other
    // words, the embedder of this component should be the source of
    // truth, not the native component.
    if (
      this._picker &&
      this.state.selectedIndex !== event.nativeEvent.newIndex
    ) {
      this._picker.setNativeProps({
        selectedIndex: this.state.selectedIndex,
      });
    }
  },
});

type Props = {
  value: any,
  label: string,
  color: string,
};

PickerIOS.Item = class extends React.Component<Props> {
  static propTypes = {
    value: PropTypes.any, // string or integer basically
    label: PropTypes.string,
    color: PropTypes.string,
  };

  render() {
    // These items don't get rendered directly.
    return null;
  }
};

var styles = StyleSheet.create({
  pickerIOS: {
    // The picker will conform to whatever width is given, but we do
    // have to set the component's height explicitly on the
    // surrounding view to ensure it gets rendered.
    height: 26,
  },
});

var RCTPickerIOS = requireNativeComponent(
  'RCTPicker' /* TODO refactor to a class that extends React.Component {
  propTypes: {
    style: itemStylePropType,
  },
}, {
  nativeOnly: {
    items: true,
    onChange: true,
    selectedIndex: true,
  },
}*/,
);

module.exports = PickerIOS;
