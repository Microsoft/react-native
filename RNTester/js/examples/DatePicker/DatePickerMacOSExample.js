/**
 * Copyright (c) 2015-present, Facebook, Inc.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 * @flow
 */
'use strict';

const React = require('react');
const ReactNative = require('react-native');
const {
  DatePickerMacOS,
  StyleSheet,
  Text,
  TextInput,
  View,
} = ReactNative;

class DatePickerExample extends React.Component<
  $FlowFixMeProps,
  $FlowFixMeState,
> {
  static defaultProps = {
    date: new Date(),
    timeZoneOffsetInHours: (-1) * (new Date()).getTimezoneOffset() / 60,
  };

  state = {
    date: this.props.date,
    timeZoneOffsetInHours: this.props.timeZoneOffsetInHours,
  };

  onDateChange = (date) => {
    this.setState({date: date});
  };

  onTimezoneChange = (event) => {
    var offset = parseInt(event.nativeEvent.text, 10);
    if (isNaN(offset)) {
      return;
    }
    this.setState({timeZoneOffsetInHours: offset});
  };

  render() {
    // Ideally, the timezone input would be a picker rather than a
    // text input, but we don't have any pickers yet :(
    return (
      <View>
        <WithLabel label="Value:">
          <Text>{
            this.state.date.toLocaleDateString() +
            ' ' +
            this.state.date.toLocaleTimeString()
          }</Text>
        </WithLabel>
        <WithLabel label="Timezone:">
          <TextInput
            onChange={this.onTimezoneChange}
            style={styles.textinput}
            value={this.state.timeZoneOffsetInHours.toString()}
          />
          <Text> hours from UTC</Text>
        </WithLabel>
        <Heading label="TextField and stepper" />
        <DatePickerMacOS
          style={styles.pickerTextField}
          date={this.state.date}
          mode="single"
          timeZoneOffsetInMinutes={this.state.timeZoneOffsetInHours * 60}
          onDateChange={this.onDateChange}
        />
        <Heading label="Clock and Calendar" />
        <DatePickerMacOS
          style={styles.pickerClock}
          pickerStyle="clock-calendar"
          date={this.state.date}
          mode="single"
          timeZoneOffsetInMinutes={this.state.timeZoneOffsetInHours * 60}
          onDateChange={this.onDateChange}
        />
        <Heading label="Only textfield" />
        <DatePickerMacOS
          style={styles.pickerTextField}
          pickerStyle="textfield"
          date={this.state.date}
          mode="single"
          timeZoneOffsetInMinutes={this.state.timeZoneOffsetInHours * 60}
          onDateChange={this.onDateChange}
        />
      </View>
    );
  }
}

class WithLabel extends React.Component<
  $FlowFixMeProps,
  $FlowFixMeState,
> {
  render() {
    return (
      <View style={styles.labelContainer}>
        <View style={styles.labelView}>
          <Text style={styles.label}>
            {this.props.label}
          </Text>
        </View>
        {this.props.children}
      </View>
    );
  }
}

class Heading extends React.Component<
  $FlowFixMeProps,
  $FlowFixMeState,
> {
  render() {
    return (
      <View style={styles.headingContainer}>
        <Text style={styles.heading}>
          {this.props.label}
        </Text>
      </View>
    );
  }
}

exports.displayName = (undefined: ?string);
exports.title = '<DatePickerMacOS>';
exports.description = 'Select dates and times using the native UIDatePicker.';
exports.examples = [
{
  title: '<DatePickerMacOS>',
  render: function(): React.Element<any> {
    return <DatePickerExample />;
  },
}];

var styles = StyleSheet.create({
  pickerTextField: {
    height: 30,
    width: 170,
  },
  pickerClock: {
    height: 150,
    width: 150,
  },
  textinput: {
    height: 26,
    width: 50,
    borderWidth: 0.5,
    borderColor: '#0f0f0f',
    padding: 4,
    fontSize: 13,
  },
  labelContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginVertical: 2,
  },
  labelView: {
    marginRight: 10,
    paddingVertical: 2,
  },
  label: {
    fontWeight: '500',
  },
  headingContainer: {
    padding: 4,
    backgroundColor: '#f6f7f8',
  },
  heading: {
    fontWeight: '500',
    fontSize: 14,
  },
});
