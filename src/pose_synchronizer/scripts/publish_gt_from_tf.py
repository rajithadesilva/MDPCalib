#!/usr/bin/env python3

import rospy
import tf2_ros
from geometry_msgs.msg import PoseStamped


class GtFromTfPublisher:

    def __init__(self) -> None:
        self.source_frame = rospy.get_param("~source_frame", "os_sensor")
        self.target_frame = rospy.get_param("~target_frame", "front_left_camera_optical_frame")
        self.topic_name = rospy.get_param("~topic_name", "/gt_extrinsics")
        self.timeout_sec = float(rospy.get_param("~timeout_sec", 30.0))

        self.publisher = rospy.Publisher(self.topic_name, PoseStamped, queue_size=1, latch=True)
        self.tf_buffer = tf2_ros.Buffer()
        self.tf_listener = tf2_ros.TransformListener(self.tf_buffer)

    def publish(self) -> None:
        timeout = rospy.Duration(self.timeout_sec)
        start = rospy.Time.now()
        rate = rospy.Rate(5)

        while not rospy.is_shutdown():
            try:
                # Publish the target frame pose expressed in the source frame.
                # For BLT this means the camera optical pose in the LiDAR frame.
                transform = self.tf_buffer.lookup_transform(self.source_frame, self.target_frame,
                                                            rospy.Time(0), rospy.Duration(1.0))
                msg = PoseStamped()
                msg.header.stamp = transform.header.stamp if transform.header.stamp != rospy.Time(
                    0) else rospy.Time.now()
                msg.header.frame_id = ""
                msg.pose.position.x = transform.transform.translation.x
                msg.pose.position.y = transform.transform.translation.y
                msg.pose.position.z = transform.transform.translation.z
                msg.pose.orientation = transform.transform.rotation
                self.publisher.publish(msg)
                rospy.loginfo("Published GT extrinsics as pose of %s in %s on %s", self.target_frame,
                              self.source_frame, self.topic_name)
                return
            except (tf2_ros.LookupException, tf2_ros.ConnectivityException,
                    tf2_ros.ExtrapolationException) as exc:
                if rospy.Time.now() - start > timeout:
                    rospy.logwarn("Timed out after %.1fs waiting for pose of %s in %s: %s. "
                                  "BLT optimization will continue without GT error metrics.", self.timeout_sec,
                                  self.target_frame, self.source_frame, exc)
                    return
                rate.sleep()


if __name__ == "__main__":
    rospy.init_node("publish_gt_from_tf")
    GtFromTfPublisher().publish()
